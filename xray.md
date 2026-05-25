# Xray VPN — Operations Manual

## Overview

A chain of xray VLESS/xhttp proxy servers managed via Ansible. Servers are deployed
and configured from a local machine; client configs are generated locally and
published to a Caddy-hosted subscription URL.

```
Client → ru_firstvds → dk_webdock → internet
                     ↘ (direct) → Russian sites (.ru)
```

`nl_llhost` is a standalone server (no chain).

`ru_firstvds` is also the **publish server** — it hosts subscription JSON files via
Caddy under `https://<domain>/<token>/configs.json`. Hosts in the `xray_publish`
inventory group are treated as publish targets.

---

## Prerequisites

- `ansible`
- `pass` (GPG password manager)
- `python3` (stdlib only — no extra packages)
- `jq`

---

## Secret store layout (`pass xray/`)

| Key                  | Contents                                      |
|----------------------|-----------------------------------------------|
| `xray/uuids`         | JSON array of all users (see below)           |
| `xray/secret_path`   | xhttp path shared by all servers              |
| `xray/subscriptions` | JSON array of named subscriptions (see below) |

### User record (`xray/uuids`)

```json
[
  {
    "name": "xray_client",
    "id": "<uuid>",
    "skip_client_config": true
  },
  {
    "name": "morjoff",
    "id": "<uuid>",
    "routing_profiles": [
      {
        "name": "full_proxy"
      }
    ]
  },
  {
    "name": "olga",
    "id": "<uuid>",
    "routing_profiles": [
      {
        "name": "selective",
        "proxy_ips": [
          "geoip:telegram"
        ],
        "proxy_domains": [
          "geosite:youtube",
          "geosite:google",
          "memrise.com"
        ]
      },
      {
        "name": "full_proxy"
      }
    ]
  }
]
```

`xray_client` is the server-to-server chaining identity — always mark it
`skip_client_config: true`.

`routing_profiles` controls the routing rules in load-balanced configs:

| Profile        | Behaviour                                                 |
|----------------|-----------------------------------------------------------|
| `full_proxy`   | All traffic → balancer                                    |
| `selective`    | Listed domains/IPs → balancer, everything else → direct   |
| `proxy_direct` | All traffic → `proxy_direct` outbound, bypassing balancer |

### Subscription record (`xray/subscriptions`)

```json
[
  {
    "name": "morjoff_vpn",
    "token": "<uuid>",
    "files": [
      {
        "path": "~/vpn/morjoff/ru_firstvds_lb_full_proxy_config.json"
      },
      {
        "path": "~/vpn/morjoff/ru_firstvds_lb_full_proxy_config.json",
        "remark": "Custom name"
      }
    ]
  }
]
```

`token` is the unguessable URL segment. Generate with:

```bash
uuidgen | tr '[:upper:]' '[:lower:]'
```

`files` supports glob patterns and an optional `remark` override per entry.

---

## Generated client configs

For each user × host, Ansible generates local JSON files under `~/vpn/<user>/`:

| File                              | Remark                     | Description                                           |
|-----------------------------------|----------------------------|-------------------------------------------------------|
| `<host>_config.json`              | `user@host`                | Direct connection                                     |
| `<host>_cdn_config.json`          | `user@host · CDN`          | Static CDN outbound                                   |
| `<host>_lb_<profile>_config.json` | `user@host · LB [Profile]` | Load-balanced: `proxy_direct` preferred, CDN fallback |

The LB config uses `burstObservatory` (3-sample probes every minute) to detect
when `proxy_direct` is dead and automatically switches to the CDN outbound via
`fallbackTag`.

---

## Scripts

### `./install-xray.sh [host]`

Full deploy: installs xray on all servers, generates client configs, merges
subscriptions, uploads to publish server.

```bash
./install-xray.sh              # all hosts
./install-xray.sh ru_firstvds  # single host
```

### `./publish-xray-client-configs.sh [host]`

Lightweight update: regenerates client configs and re-publishes subscriptions.
Use this after changing `xray/uuids` or `xray/subscriptions` without needing
to redeploy the servers.

```bash
./publish-xray-client-configs.sh
./publish-xray-client-configs.sh ru_firstvds
```

Both scripts run in three stages:

1. **Generate** — Ansible renders per-host JSON configs to `~/vpn/<user>/`
2. **Merge** — `scripts/merge-subscriptions.py` globs + merges files into
   `~/vpn/subscriptions/<name>/configs.json`, applying any remark overrides
3. **Publish** — Ansible copies merged bundles to `/var/www/xray-configs/<token>/`
   on the publish server, cleaning up stale token directories

---

## Subscription URLs

After publishing, subscription URLs are printed by Ansible:

```
https://clumsypanda.mooo.com/<token>/configs.json
```

Import this URL into your xray client (v2rayN, NekoBox, etc.).

---

## Common operations

### Add a user

1. `pass edit xray/uuids` — add a new entry with a fresh UUID
2. `pass edit xray/subscriptions` — add the user's config files to the
   relevant subscription's `files` list
3. `./install-xray.sh` — deploy updated server config and publish new client configs

### Add a subscription

1. Generate a token: `uuidgen | tr '[:upper:]' '[:lower:]'`
2. `pass edit xray/subscriptions` — add a new subscription entry
3. `./publish-xray-client-configs.sh` — publish (directories are created automatically)

### Change routing rules for a user

1. `pass edit xray/uuids` — update `routing_profiles` for the user
2. `./publish-xray-client-configs.sh` — regenerate and republish

### Add a new server

1. Add host to `ansible/inventory/xray.yml` with `domain`, `ansible_host`, and
   optionally `cdn_domain`/`server_ip`, `next_address`, `xray_xhttp_extra_settings`,
   `local_exit_rules`, `warp_outbound_enabled`
2. `./install-xray.sh <new_host>`
3. Add the new host's config files to subscriptions as needed
4. `./publish-xray-client-configs.sh`

---

## Inventory host vars reference

| Variable                                 | Required | Description                                               |
|------------------------------------------|----------|-----------------------------------------------------------|
| `domain`                                 | ✓        | Public domain (FreeDNS), used for TLS and Caddy           |
| `cdn_domain`                             |          | CDN domain for SNI in CDN/LB client configs               |
| `server_ip`                              |          | Real IP behind CDN (enables CDN client config generation) |
| `next_address`                           |          | Next hop domain for server chaining                       |
| `next_address_xray_xhttp_extra_settings` |          | xhttp settings for the chain outbound                     |
| `xray_xhttp_extra_settings`              |          | Extra xhttp padding/obfuscation settings                  |
| `warp_outbound_enabled`                  |          | Enable Cloudflare WARP outbound                           |
| `local_exit_rules`                       |          | List of `{domains, outbound}` rules for local geo exit    |

## Inventory groups reference

| Group          | Description                                                                 |
|----------------|-----------------------------------------------------------------------------|
| `xray`         | All xray hosts — full role is applied                                       |
| `xray_publish` | Hosts that serve subscription files via Caddy; publish scripts target these |
