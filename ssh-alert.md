# ssh-alert — SSH Auth Tripwire

## Overview

A per-host detection tripwire: it watches `journalctl -u ssh` for successful logins
and pings Telegram whenever a session is authenticated by a key/IP combination that
host hasn't seen before. It runs after authentication succeeds — it never blocks,
delays, or rejects a login. Pure detection, no prevention.

```
sshd (LogLevel VERBOSE) --journald--> ssh-alert.py --journalctl --follow-->
    classify against /var/lib/ssh-alert/state.db (sqlite)
        --new/unusual--> outbox table --worker thread--> Telegram
```

Each host keeps its own state — there's no central server and no cross-host
correlation. `ansible/roles/ssh_alert` installs it as an unprivileged systemd
service (`ssh-alert.py`, stdlib-only Python, no pip dependencies). There's no
separate inventory group for it — the role runs right after `ssh_hardening` in
`ansible/xray.yml` and `ansible/k3s.yml`, so every host those playbooks already
manage (`xray`, `k3s_server`, `k3s_agent`) gets the tripwire automatically on
its normal deploy. `ansible/headscale.yml` doesn't include it yet (that
inventory group is currently empty/unused) — add the same two-line pairing
there if that host comes back into use.

An accepted login is classified:

| Situation | Tier |
|---|---|
| Fingerprint never authenticated on this host before | **HIGH** |
| Known fingerprint, brand new IP | **MEDIUM** |
| Known fingerprint, new IP in an already-seen /24 (v4) or /64 (v6) | **LOW** |
| A fingerprint reappears after 90+ days of silence (configurable), same IP | **MEDIUM** |
| A fingerprint reappears after 90+ days of silence, on a new IP | **HIGH** |

Password/keyboard-interactive logins are handled the same way but with an empty
fingerprint (matched on `user`+`ip` instead) — the alert text notes the
degradation. Automation keys (CI runners, dynamic-IP control nodes) can be listed
in `config.json` to suppress or downgrade their routine new-IP noise; a genuinely
new fingerprint for them still always alerts.

There's deliberately no heartbeat/dead-man's-switch, no prune-by-authorized_keys
job (a long-silent key reappearing is caught by the dormancy check above instead —
see the role's tasks/main.yml for why), and no failed-login alerting (internet-facing
hosts see constant scanning noise; `handle_accepted_auth` in `ssh-alert.py` is a
documented hook where a future successful-after-failures feature could plug in).

---

## Prerequisites

- Target host is Debian/Ubuntu (Ubuntu 24.04+ assumed) with systemd and journald,
  and its sshd is the `ssh.service`/`ssh.socket` unit (Debian/Ubuntu default).
- `LogLevel VERBOSE` must already be set in `sshd_config` — without it sshd never
  logs key fingerprints and the tripwire is blind to *which* key authenticated.
  The role checks this via `sshd -T` and refuses to proceed with a clear message
  if it's missing; it does not modify `sshd_config` itself (see `ssh_hardening`
  role for that).
- A Telegram bot token and chat ID stored in `pass` (see below).

### Setting up the Telegram bot

1. Message [@BotFather](https://t.me/BotFather) on Telegram, send `/newbot`, and
   follow the prompts (pick a display name, then a unique `_bot`-suffixed
   username). BotFather replies with an API token that looks like
   `123456789:AAExampleTokenTextGoesHere`. That's `TELEGRAM_BOT_TOKEN`.
2. Start a chat with your new bot (search its username, hit Start) and send it any
   message — the bot can't message you first.
3. Fetch your chat ID:
   `curl -s "https://api.telegram.org/bot<token>/getUpdates"` and read the
   `message.chat.id` field from the reply (a plain integer; negative if you instead
   add the bot to a group and want alerts posted there). That's `TELEGRAM_CHAT_ID`.
4. Store both in `pass`:
   ```bash
   pass insert ssh-alert/telegram_bot_token
   pass insert ssh-alert/telegram_chat_id
   ```

---

## Secret store layout (`pass ssh-alert/`)

| Key | Contents |
|---|---|
| `ssh-alert/telegram_bot_token` | Bot API token from BotFather |
| `ssh-alert/telegram_chat_id` | Destination chat ID for alerts |

---

## Deploy

There's no dedicated install script — `ssh_alert` rides along with whichever
playbook already provisions the host, right after `ssh_hardening`:

```bash
./install-xray.sh --limit <host> --tags ssh_hardening,ssh_alert   # xray hosts
./install-k3s.sh --limit <host> --tags ssh_hardening,ssh_alert    # k3s hosts
```

Both scripts now also pull `ssh-alert/telegram_bot_token` /
`ssh-alert/telegram_chat_id` from `pass` and pass them through. Drop
`--limit`/`--tags` for a normal full deploy of that playbook — the tripwire
just comes along with everything else for that host. `personal-fedora-ai`
(`home.yml`) isn't covered by either playbook, so it's excluded by
construction — it's a local dev container, not a server this is meant to
watch.

The role does **not** pre-seed `state.db` — every account/IP combo alerts as
new the first time it's seen after install, including ones already in routine
use. That's a deliberate choice for a low-traffic homelab: better to see
everything once than to silently trust whatever was already logged. If you
ever deploy to a much noisier host and want to avoid a wall of day-one alerts,
`ssh-alert.py` still supports seeding manually — it's just not run
automatically:
```bash
sudo -u ssh-alert /usr/local/bin/ssh-alert.py --seed --since "30 days ago"
```

---

## Verification

```bash
# On the target host:
journalctl -u ssh-alert -f

# From a known key/IP: silence. From a fresh keypair: one [HIGH] Telegram message.

# Confirm the service survives journald hiccups:
pkill -f 'journalctl.*-u ssh'
# ssh-alert restarts journalctl with backoff and keeps parsing — no gap, no replay
# (journald's --cursor-file resumes it exactly).

# Confirm the token never leaks:
ps aux | grep ssh-alert          # no token visible
stat -c '%a %U' /etc/ssh-alert/env   # 600 ssh-alert

# Inspect state directly:
sqlite3 /var/lib/ssh-alert/state.db 'select * from seen;'
sqlite3 /var/lib/ssh-alert/state.db 'select * from outbox;'
```

---

## Config (`/etc/ssh-alert/config.json`, templated from role defaults)

```json
{
  "dormancy_days_default": 90,
  "dormancy_overrides": {"SHA256:...": 365},
  "suppressed_fingerprints": {"SHA256:...": "suppress"},
  "rate_limit_per_minute": 5
}
```

- `dormancy_overrides` — per-fingerprint override of the 90-day silence
  threshold (e.g. a CI key that only runs quarterly).
- `suppressed_fingerprints` — fingerprints treated as automation (CI runners,
  dynamic-IP control nodes). Value is `"low"` (downgrade new-IP alerts to LOW)
  or `"suppress"` (drop them entirely). New-fingerprint alerts always fire
  regardless.

Set these via the role's `ssh_alert_dormancy_overrides` /
`ssh_alert_suppressed_fingerprints` / `ssh_alert_dormancy_days_default` vars
(`ansible/roles/ssh_alert/defaults/main.yml`, or `-e` on the playbook run) and
re-deploy.

---

## Non-goals

- No heartbeat / dead-man's-switch — a root-level attacker can kill the agent;
  that gap is accepted.
- No central server, shared state, or cross-host correlation.
- No alerting on failed auth attempts (internet-facing hosts see constant scanner
  noise). A successful-login-after-failures feature has a clean hook
  (`handle_accepted_auth` in `ssh-alert.py`) but isn't implemented.
- No web UI, dashboard, metrics endpoint, packaging, or container images.
- No non-stdlib Python dependencies.

---

## Where it's applied

| Playbook | Groups covered | Runs `ssh_alert`? |
|---|---|---|
| `ansible/xray.yml` | `xray` | Yes, right after `ssh_hardening` |
| `ansible/k3s.yml` | `k3s_server`, `k3s_agent` | Yes, right after `ssh_hardening` |
| `ansible/headscale.yml` | `headscale` (currently empty) | Not yet — add the same pairing if revived |
