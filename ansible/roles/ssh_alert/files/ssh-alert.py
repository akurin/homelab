#!/usr/bin/env python3
import ipaddress
import json
import os
import re
import signal
import socket
import sqlite3
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

DB_PATH = "/var/lib/ssh-alert/state.db"
CURSOR_PATH = "/var/lib/ssh-alert/cursor"
CONFIG_PATH = "/etc/ssh-alert/config.json"
SSH_UNIT = "ssh"
HOSTNAME = socket.gethostname()

SCHEMA = """
CREATE TABLE IF NOT EXISTS seen (
  id INTEGER PRIMARY KEY,
  user TEXT NOT NULL,
  keytype TEXT,
  fingerprint TEXT NOT NULL DEFAULT '',
  ip TEXT NOT NULL,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 1,
  UNIQUE(user, fingerprint, ip)
);

CREATE TABLE IF NOT EXISTS outbox (
  id INTEGER PRIMARY KEY,
  created TEXT NOT NULL,
  body TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt TEXT NOT NULL
);
"""

DEFAULT_CONFIG = {
    "dormancy_days_default": 90,
    "dormancy_overrides": {},          # fingerprint -> days
    "suppressed_fingerprints": {},     # fingerprint -> "low" or "suppress"
    "rate_limit_per_minute": 5,
}

ACCEPTED_RE = re.compile(
    r"^Accepted (?P<method>[\w./-]+) for (?P<user>\S+) from (?P<ip>\S+) "
    r"port (?P<port>\d+) ssh2(?::\s*(?P<keytype>\S+)\s+(?P<fingerprint>\S+))?$"
)

TIER_RE = re.compile(r"^\[(HIGH|MEDIUM|LOW)\]")
USER_LINE_RE = re.compile(r"^user:\s*(\S+)", re.M)
FROM_LINE_RE = re.compile(r"^from:\s*(\S+)", re.M)
TIER_ORDER = {"LOW": 1, "MEDIUM": 2, "HIGH": 3}


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH) as f:
            cfg.update(json.load(f))
    except FileNotFoundError:
        pass
    return cfg


def utcnow_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def parse_accepted(message):
    m = ACCEPTED_RE.match(message)
    if not m:
        return None
    return {
        "user": m.group("user"),
        "ip": m.group("ip"),
        "keytype": m.group("keytype") or "",
        "fingerprint": m.group("fingerprint") or "",
        "degraded": m.group("fingerprint") is None,
    }


def event_from_journal_entry(entry):
    message = entry.get("MESSAGE", "")
    parsed = parse_accepted(message)
    if parsed is None:
        return None
    us = int(entry["__REALTIME_TIMESTAMP"])
    parsed["ts"] = datetime.fromtimestamp(us / 1_000_000, tz=timezone.utc).isoformat(
        timespec="seconds"
    )
    return parsed


class Store:
    """Single shared sqlite3 connection guarded by a lock.

    Event volume here is a handful of logins a day, so one lock serializing
    the parser thread and the outbox worker is simpler than juggling
    per-thread connections, and avoids "database is locked" errors outright.
    """

    def __init__(self, path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        self.lock = threading.Lock()
        self.conn = sqlite3.connect(path, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL")
        with self.lock:
            self.conn.executescript(SCHEMA)
            self.conn.commit()

    def fingerprint_scope(self, fingerprint, user):
        # A blank fingerprint (password/keyboard-interactive auth) isn't a
        # real identity, so unlike a real key it must be scoped per-user —
        # otherwise any two users' password logins would look like "the same
        # known fingerprint" to each other.
        if fingerprint == "":
            return "fingerprint = '' AND user = ?", (user,)
        return "fingerprint = ?", (fingerprint,)

    def get_row(self, user, fingerprint, ip):
        with self.lock:
            cur = self.conn.execute(
                "SELECT id, first_seen, last_seen, count FROM seen "
                "WHERE user=? AND fingerprint=? AND ip=?",
                (user, fingerprint, ip),
            )
            return cur.fetchone()

    def fingerprint_summary(self, fingerprint, user):
        """Aggregate first_seen/last_seen/count/known-ips across every row
        sharing this fingerprint's identity scope, used both to decide
        tiers and to render the 'first seen ..., N sessions' alert line."""
        clause, params = self.fingerprint_scope(fingerprint, user)
        with self.lock:
            cur = self.conn.execute(
                f"SELECT MIN(first_seen), MAX(last_seen), SUM(count), COUNT(*) "
                f"FROM seen WHERE {clause}",
                params,
            )
            first_seen, last_seen, total_count, rows = cur.fetchone()
            if rows == 0:
                return None
            ips = self.conn.execute(
                f"SELECT ip FROM seen WHERE {clause}", params
            ).fetchall()
        return {
            "first_seen": first_seen,
            "last_seen": last_seen,
            "count": total_count,
            "ips": [r[0] for r in ips],
        }

    def upsert_match(self, row_id, ts):
        with self.lock:
            self.conn.execute(
                "UPDATE seen SET last_seen=?, count=count+1 WHERE id=?", (ts, row_id)
            )
            self.conn.commit()

    def insert_new(self, user, keytype, fingerprint, ip, ts):
        with self.lock:
            self.conn.execute(
                "INSERT INTO seen(user, keytype, fingerprint, ip, first_seen, last_seen) "
                "VALUES (?,?,?,?,?,?)",
                (user, keytype, fingerprint, ip, ts, ts),
            )
            self.conn.commit()

    def enqueue(self, body):
        with self.lock:
            now = utcnow_iso()
            self.conn.execute(
                "INSERT INTO outbox(created, body, next_attempt) VALUES (?,?,?)",
                (now, body, now),
            )
            self.conn.commit()

    def due_outbox(self, now):
        with self.lock:
            return self.conn.execute(
                "SELECT id, body, attempts FROM outbox WHERE next_attempt<=? ORDER BY id",
                (now,),
            ).fetchall()

    def drop_outbox(self, ids):
        with self.lock:
            self.conn.executemany("DELETE FROM outbox WHERE id=?", [(i,) for i in ids])
            self.conn.commit()

    def retry_outbox(self, row_id, attempts, next_attempt):
        with self.lock:
            self.conn.execute(
                "UPDATE outbox SET attempts=?, next_attempt=? WHERE id=?",
                (attempts, next_attempt, row_id),
            )
            self.conn.commit()


def same_subnet(ip, known_ips):
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    prefix = 24 if addr.version == 4 else 64
    for other in known_ips:
        try:
            other_addr = ipaddress.ip_address(other)
        except ValueError:
            continue
        if other_addr.version != addr.version:
            continue
        net = ipaddress.ip_network(f"{other_addr}/{prefix}", strict=False)
        if addr in net:
            return True
    return False


def dormancy_days_for(config, fingerprint):
    return config["dormancy_overrides"].get(fingerprint, config["dormancy_days_default"])


def days_between(a_iso, b_iso):
    a = datetime.fromisoformat(a_iso)
    b = datetime.fromisoformat(b_iso)
    return abs((b - a).total_seconds()) / 86400


def format_alert(tier, headline, user, keytype, fingerprint, ip, degraded, detail_lines):
    lines = [f"[{tier}] {HOSTNAME}", headline, f"user:  {user}"]
    if fingerprint:
        lines.append(f"key:   {keytype} {fingerprint}")
    else:
        lines.append("key:   (none)")
    lines.append(f"from:  {ip}")
    lines.append(f"geoip: https://ipinfo.io/{ip}")
    if degraded:
        lines.append(
            "Degraded: non-publickey auth, matched on (user, ip) only — no fingerprint available."
        )
    lines.extend(detail_lines)
    return "\n".join(lines)


def handle_accepted_auth(store, config, event):
    """The single entry point every 'Accepted' journal line feeds into.

    Hook for a future failed-then-succeeded correlation feature: that would
    slot in here, checking recent failed attempts for the same (user, ip)
    before classifying — deliberately not implemented (see non-goals).
    """
    user, keytype, fingerprint, ip, ts = (
        event["user"],
        event["keytype"],
        event["fingerprint"],
        event["ip"],
        event["ts"],
    )
    degraded = event["degraded"]

    prior = store.fingerprint_summary(fingerprint, user)
    row = store.get_row(user, fingerprint, ip)

    if row is not None:
        row_id, first_seen, last_seen, count = row
        gap = days_between(last_seen, ts)
        store.upsert_match(row_id, ts)
        threshold = dormancy_days_for(config, fingerprint)
        if gap > threshold:
            body = format_alert(
                "MEDIUM",
                f"Key reactivated after {int(gap)} days of silence",
                user,
                keytype,
                fingerprint,
                ip,
                degraded,
                [f"first seen {first_seen[:10]}, {count + 1} sessions"],
            )
            store.enqueue(body)
        return

    store.insert_new(user, keytype, fingerprint, ip, ts)

    if prior is None:
        body = format_alert(
            "HIGH",
            "New key authenticated" if fingerprint else "New credential authenticated",
            user,
            keytype,
            fingerprint,
            ip,
            degraded,
            ["This fingerprint has never authenticated on this host."],
        )
        store.enqueue(body)
        return

    # Known fingerprint, but this exact IP hasn't been seen for it before.
    dormant = fingerprint and days_between(prior["last_seen"], ts) > dormancy_days_for(
        config, fingerprint
    )
    if dormant:
        tier = "HIGH"
        headline = "Dormant key resurfaced on a new IP"
    elif same_subnet(ip, prior["ips"]):
        tier = "LOW"
        headline = "Known key, new IP in an already-seen subnet"
    else:
        tier = "MEDIUM"
        headline = "Known key, new IP"

    if fingerprint in config["suppressed_fingerprints"] and tier != "HIGH":
        action = config["suppressed_fingerprints"][fingerprint]
        if action == "suppress":
            return
        if action == "low":
            tier = "LOW"

    body = format_alert(
        tier,
        headline,
        user,
        keytype,
        fingerprint,
        ip,
        degraded,
        [f"first seen {prior['first_seen'][:10]}, {prior['count'] + 1} sessions"],
    )
    store.enqueue(body)


def build_aggregate(rows):
    users, ips = set(), set()
    worst_tier, worst_body = "LOW", rows[0][1]
    for _id, body, _attempts in rows:
        m = TIER_RE.match(body)
        tier = m.group(1) if m else "LOW"
        if TIER_ORDER[tier] >= TIER_ORDER[worst_tier]:
            worst_tier, worst_body = tier, body
        u = USER_LINE_RE.search(body)
        if u:
            users.add(u.group(1))
        f = FROM_LINE_RE.search(body)
        if f:
            ips.add(f.group(1))
    summary = (
        f"[{worst_tier}] {HOSTNAME}\n"
        f"{len(rows)} events from {len(ips)} address(es), {len(users)} user(s)\n\n"
        f"Highest-tier detail:\n{worst_body}"
    )
    return summary


def send_telegram(token, chat_id, text):
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    data = urllib.parse.urlencode({"chat_id": chat_id, "text": text}).encode()
    req = urllib.request.Request(url, data=data)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status == 200
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def outbox_worker(store, config, token, chat_id, stop_event):
    sent_at = []  # sliding window of recent successful sends, for rate limiting
    while not stop_event.wait(5):
        now_dt = datetime.now(timezone.utc)
        sent_at = [t for t in sent_at if now_dt - t < timedelta(minutes=1)]
        rows = store.due_outbox(utcnow_iso())
        if not rows:
            continue

        limit = config["rate_limit_per_minute"]
        budget = max(0, limit - len(sent_at))
        if budget == 0:
            continue

        # Every batch entry is (ids, body): a single-id list for an
        # individual alert, or the full overflow id list for one aggregated
        # message — so success/failure bookkeeping below doesn't need to
        # special-case aggregation at all.
        if len(rows) > budget > 1:
            individually, overflow = rows[: budget - 1], rows[budget - 1 :]
            batch = [([r[0]], r[1]) for r in individually]
            batch.append(([r[0] for r in overflow], build_aggregate(overflow)))
        else:
            batch = [([r[0]], r[1]) for r in rows[:budget]]

        attempts_by_id = {r[0]: r[2] for r in rows}
        sent_ids = []
        for ids, body in batch:
            if send_telegram(token, chat_id, body):
                sent_at.append(datetime.now(timezone.utc))
                sent_ids.extend(ids)
            else:
                for row_id in ids:
                    attempts = attempts_by_id[row_id] + 1
                    backoff = min(3600, 30 * (2 ** attempts))
                    next_attempt = (
                        datetime.now(timezone.utc) + timedelta(seconds=backoff)
                    ).isoformat(timespec="seconds")
                    store.retry_outbox(row_id, attempts, next_attempt)
        if sent_ids:
            store.drop_outbox(sent_ids)


def follow_journal(stop_event):
    """Yields parsed journal JSON entries forever, restarting journalctl
    with exponential backoff whenever it exits (journald restart, log
    rotation, crash). --cursor-file makes journald itself responsible for
    resume position, so a restart here never replays or drops events."""
    backoff = 1
    while not stop_event.is_set():
        proc = subprocess.Popen(
            [
                "journalctl",
                "-u",
                SSH_UNIT,
                "-o",
                "json",
                "--follow",
                f"--cursor-file={CURSOR_PATH}",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        try:
            for line in proc.stdout:
                backoff = 1
                line = line.strip()
                if not line:
                    continue
                try:
                    yield json.loads(line)
                except json.JSONDecodeError:
                    continue
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        if stop_event.is_set():
            return
        stop_event.wait(backoff)
        backoff = min(60, backoff * 2)


def seed(store, since):
    proc = subprocess.run(
        ["journalctl", "-u", SSH_UNIT, "--since", since, "-o", "json"],
        capture_output=True,
        text=True,
        check=True,
    )
    last_cursor = None
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        last_cursor = entry.get("__CURSOR", last_cursor)
        event = event_from_journal_entry(entry)
        if event is None:
            continue
        if store.get_row(event["user"], event["fingerprint"], event["ip"]) is not None:
            continue
        store.insert_new(
            event["user"], event["keytype"], event["fingerprint"], event["ip"], event["ts"]
        )
    if last_cursor is not None:
        os.makedirs(os.path.dirname(CURSOR_PATH), exist_ok=True)
        tmp = CURSOR_PATH + ".tmp"
        with open(tmp, "w") as f:
            f.write(last_cursor)
        os.replace(tmp, CURSOR_PATH)


def main():
    store = Store(DB_PATH)

    if "--seed" in sys.argv:
        since = "30 days ago"
        if "--since" in sys.argv:
            since = sys.argv[sys.argv.index("--since") + 1]
        seed(store, since)
        return

    config = load_config()
    token = os.environ["TELEGRAM_BOT_TOKEN"]
    chat_id = os.environ["TELEGRAM_CHAT_ID"]

    stop_event = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop_event.set())
    signal.signal(signal.SIGINT, lambda *_: stop_event.set())

    worker = threading.Thread(
        target=outbox_worker, args=(store, config, token, chat_id, stop_event), daemon=True
    )
    worker.start()

    for entry in follow_journal(stop_event):
        event = event_from_journal_entry(entry)
        if event is None:
            continue
        handle_accepted_auth(store, config, event)

    stop_event.set()
    worker.join(timeout=10)


if __name__ == "__main__":
    main()
