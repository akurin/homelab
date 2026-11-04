# ssh-alert — SSH Auth Tripwire

## Overview

Per-host detection tripwire: it watches `journalctl -u ssh` for successful logins and sends a
Telegram message when a session is authenticated by a key/IP combination the host has not seen. It
runs after authentication — it never blocks, delays or rejects a login.

```
sshd (LogLevel VERBOSE) --journald--> ssh-alert.py --journalctl --follow-->
    classify against /var/lib/ssh-alert/state.db (sqlite)
        --new/unusual--> outbox table --worker thread--> Telegram
```

Each host keeps its own state: no central server, no cross-host correlation. The `ssh_alert` role
installs it as an unprivileged systemd service (stdlib-only Python) and runs right after
`ssh_hardening` in `ansible/xray.yml` and `ansible/k3s.yml`, so every host those playbooks manage
gets it. `ansible/headscale.yml` does not include it (that group is empty); add the same pairing if
the host comes back into use.

| Situation | Tier |
|---|---|
| Fingerprint never authenticated on this host before | **HIGH** |
| Known fingerprint, brand new IP | **MEDIUM** |
| Known fingerprint, new IP in an already-seen /24 (v4) or /64 (v6) | **LOW** |
| Fingerprint reappears after 90+ days of silence (configurable), same IP | **MEDIUM** |
| Fingerprint reappears after 90+ days of silence, new IP | **HIGH** |

Password/keyboard-interactive logins are matched on `user`+`ip` with an empty fingerprint, and the
alert says so. Automation keys (CI runners, dynamic-IP control nodes) can be listed in `config.json`
to suppress or downgrade their routine new-IP noise; a genuinely new fingerprint always alerts.

Deliberately absent: heartbeat/dead-man's switch, prune-by-`authorized_keys` (a long-silent key is
caught by the dormancy check), and failed-login alerting (`handle_accepted_auth` in `ssh-alert.py`
is the hook for a future successful-after-failures feature).

## Prerequisites

- Debian/Ubuntu with systemd and journald, sshd as `ssh.service`/`ssh.socket`.
- `LogLevel VERBOSE` in `sshd_config`; without it sshd logs no key fingerprints. The role checks
  with `sshd -T` and refuses to proceed otherwise (it does not edit `sshd_config` — `ssh_hardening`).
- Telegram bot token and chat ID in `pass`.

### Telegram bot

1. Message [@BotFather](https://t.me/BotFather), send `/newbot`, follow the prompts. The reply is
   the token (`123456789:AAExampleTokenTextGoesHere`).
2. Start a chat with the bot and send it any message — it cannot message you first.
3. `curl -s "https://api.telegram.org/bot<token>/getUpdates"` and read `message.chat.id` (an integer;
   negative for a group).
4. `pass insert ssh-alert/telegram_bot_token` and `pass insert ssh-alert/telegram_chat_id`.

## Secret store (`pass ssh-alert/`)

| Key | Contents |
|---|---|
| `ssh-alert/telegram_bot_token` | Bot API token from BotFather |
| `ssh-alert/telegram_chat_id` | Destination chat ID |

## Deploy

There is no dedicated script; `ssh_alert` rides along with the playbook that provisions the host:

```bash
./install-xray.sh --limit <host> --tags ssh_hardening,ssh_alert   # xray hosts
./install-k3s.sh --limit <host> --tags ssh_hardening,ssh_alert    # k3s hosts
```

Both scripts pull the two `pass` entries and pass them through. Drop `--limit`/`--tags` for a
normal full deploy. `tunnel_clients` hosts are not covered by either playbook.

`state.db` is not pre-seeded: every account/IP combination alerts as new the first time after
install, including ones already in routine use (deliberate for a low-traffic homelab).

## Verification

```bash
journalctl -u ssh-alert -f
# Known key/IP: silence. Fresh keypair: one [HIGH] Telegram message.

pkill -f 'journalctl.*-u ssh'
# ssh-alert restarts journalctl with backoff and resumes from its cursor: no gap, no replay.

ps aux | grep ssh-alert              # no token visible
stat -c '%a %U' /etc/ssh-alert/env   # 600 ssh-alert

sqlite3 /var/lib/ssh-alert/state.db 'select * from seen;'
sqlite3 /var/lib/ssh-alert/state.db 'select * from outbox;'
```

## Config (`/etc/ssh-alert/config.json`, templated from role defaults)

```json
{
  "dormancy_days_default": 90,
  "dormancy_overrides": {"SHA256:...": 365},
  "suppressed_fingerprints": {"SHA256:...": "suppress"},
  "rate_limit_per_minute": 5
}
```

- `dormancy_overrides` — per-fingerprint silence threshold (e.g. a CI key that runs quarterly).
- `suppressed_fingerprints` — automation keys; value `"low"` downgrades new-IP alerts, `"suppress"`
  drops them. New-fingerprint alerts always fire.

Set via the role's `ssh_alert_dormancy_overrides`, `ssh_alert_suppressed_fingerprints` and
`ssh_alert_dormancy_days_default` (`ansible/roles/ssh_alert/defaults/main.yml` or `-e`), then
re-deploy.

## Non-goals

- No heartbeat / dead-man's switch (a root-level attacker can kill the agent; accepted).
- No central server, shared state or cross-host correlation.
- No failed-auth alerting (internet-facing hosts see constant scanner noise).
- No web UI, metrics endpoint, packaging or container images; no non-stdlib dependencies.

## Where it's applied

| Playbook | Groups | Runs `ssh_alert`? |
|---|---|---|
| `ansible/xray.yml` | `xray` | yes, after `ssh_hardening` |
| `ansible/k3s.yml` | `k3s_server`, `k3s_agent` | yes, after `ssh_hardening` |
| `ansible/headscale.yml` | `headscale` (empty) | no — add the pairing if revived |
