# Xray VPN — Operations Manual

## Overview

A chain of xray VLESS/xhttp proxy servers managed via Ansible. Servers are deployed
and configured from a local machine; client configs are generated locally and
published to a Caddy-hosted subscription URL.

```
Client → ru-firstvds → dk-webdock → internet
                     ↘ (direct) → Russian sites (.ru)
```

`nl-vdsina` is a standalone server (no chain).

`ru-firstvds` is also the **publish server** — it hosts subscription JSON files via
Caddy under `https://<domain>/subscriptions/<token>`. Hosts in the `xray_publish`
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
| `xray/protonvpn`     | JSON array of named ProtonVPN WireGuard configs (see below) |

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
    "configs": [
      {
        "name": "selective",
        "routing_rules": [
          {
            "type": "field",
            "ip": [
              "geoip:telegram"
            ],
            "balancerTag": "balancer"
          },
          {
            "type": "field",
            "domain": [
              "geosite:youtube",
              "geosite:google"
            ],
            "balancerTag": "balancer"
          },
          {
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": "direct"
          }
        ]
      },
      {
        "name": "full_proxy",
        "routing_rules": [
          {
            "type": "field",
            "network": "tcp,udp",
            "balancerTag": "balancer"
          }
        ]
      }
    ]
  }
]
```

`xray_client` is the server-to-server chaining identity — always mark it
`skip_client_config: true`.

Each user can have multiple named `configs`. Each config generates one LB client config file
and contains a `routing_rules` array of raw xray routing rule objects, injected after the
fixed infrastructure rules (bittorrent→direct, socks_direct→direct).

Available outbound tags in LB configs:

| Tag            | Description                                                      |
|----------------|------------------------------------------------------------------|
| `balancer`     | Load-balanced proxy (proxy_direct preferred, proxy_cdn fallback) |
| `proxy_direct` | Direct connection to server, bypassing balancer                  |
| `direct`       | Local internet (no proxy)                                        |

### Subscription record (`xray/subscriptions`)

```json
[
  {
    "name": "morjoff_vpn",
    "token": "<uuid>",
    "files": [
      {
        "path": "~/vpn/morjoff/ru-firstvds_lb_full_proxy_config.json"
      },
      {
        "path": "~/vpn/morjoff/ru-firstvds_lb_full_proxy_config.json",
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

### ProtonVPN config record (`xray/protonvpn`)

```json
[
  {
    "name": "nl-free-126",
    "private_key": "<Interface PrivateKey>",
    "address": ["10.2.0.2/32", "2a07:b944::2:2/128"],
    "public_key": "<Peer PublicKey>",
    "endpoint": "<Peer Endpoint, e.g. 185.107.56.69:51820>"
  }
]
```

Field values come straight from the WireGuard `.conf` file ProtonVPN gives you for a
device. `address` is always a JSON array — split the `.conf` file's comma-separated
`Interface Address` line into one entry per item (one entry if it's IPv4-only, two
for dual-stack). `allowed_ips` (default `["0.0.0.0/0", "::/0"]`) and
`persistent_keepalive` (default `25`) may be overridden per entry but normally don't
need to be.

A ProtonVPN WireGuard config is tied to a single device — only one xray server can
use a given entry at a time. Add one entry per server that needs a ProtonVPN exit,
each generated as a separate device/config in the ProtonVPN dashboard.

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

### `./install-xray.sh [ansible-playbook args...]`

Full deploy: installs xray on all servers, generates client configs, merges
subscriptions, uploads to publish server. Any arguments are passed straight
through to every `ansible-playbook` invocation in the script.

```bash
./install-xray.sh                       # all hosts
./install-xray.sh --limit ru-firstvds   # single host
```

### `./publish-xray-client-configs.sh [ansible-playbook args...]`

Lightweight update: regenerates client configs and re-publishes subscriptions.
Use this after changing `xray/uuids` or `xray/subscriptions` without needing
to redeploy the servers. Arguments are passed straight through to every
`ansible-playbook` invocation in the script.

```bash
./publish-xray-client-configs.sh
./publish-xray-client-configs.sh --limit ru-firstvds
```

`install-xray.sh` runs four stages:

1. **Deploy** — Ansible deploys xray + Caddy config to all servers
2. **Generate** — Ansible renders per-host JSON configs to `~/vpn/<user>/`
3. **Merge** — `scripts/merge-subscriptions.py` globs + merges files into
   `~/vpn/subscriptions/<name>/configs.json`, applying any remark overrides
4. **Publish** — Ansible copies merged bundles to `/var/www/xray-configs/<token>/`
   on the publish server, cleaning up stale token directories

`publish-xray-client-configs.sh` runs four stages:

1. **Generate** — Ansible renders per-host JSON configs to `~/vpn/<user>/`
2. **Merge** — `scripts/merge-subscriptions.py` globs + merges files into
   `~/vpn/subscriptions/<name>/configs.json`, applying any remark overrides
3. **Publish** — Ansible copies merged bundles to `/var/www/xray-configs/<token>/`
   on the publish server, cleaning up stale token directories
4. **Caddy reload** — updates the Caddyfile with current token routes and reloads Caddy

---

## Subscription URLs

After publishing, subscription URLs are printed by Ansible:

```
https://clumsypanda.mooo.com/subscriptions/<token>
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
   `local_exit_rules`, `warp_outbound_enabled`, `protonvpn_config_name`
2. `./install-xray.sh <new_host>`
3. Add the new host's config files to subscriptions as needed
4. `./publish-xray-client-configs.sh`

### Switch a server's exit to ProtonVPN

1. `pass edit xray/protonvpn` — add an entry with the WireGuard config values for
   a device dedicated to this server (see [ProtonVPN config
   record](#protonvpn-config-record-xrayprotonvpn))
2. Set `protonvpn_config_name: <entry name>` on the host in
   `ansible/inventory/xray.yml`
3. `./install-xray.sh --limit <host>`

A server picks its egress from whichever of these is defined, in this priority
order: `next_address` (chain to next hop) → `warp_outbound_enabled` →
`protonvpn_config_name` → its own IP. Only set one of `warp_outbound_enabled` /
`protonvpn_config_name` on a given host — if both are set, WARP wins.

---

## Inventory host vars reference

| Variable                                 | Required | Description                                                               |
|------------------------------------------|----------|---------------------------------------------------------------------------|
| `domain`                                 | ✓        | Public domain, used for TLS and Caddy                                     |
| `dns`                                    | ✓        | DNS provider: `freedns` (auto-updated via role) or `external` (manual)    |
| `cdn_domain`                             |          | CDN domain for SNI in CDN/LB client configs                               |
| `server_ip`                              |          | Real IP behind CDN (enables CDN client config generation)                 |
| `next_address`                           |          | Next hop domain for server chaining                                       |
| `next_address_xray_xhttp_extra_settings` |          | xhttp settings for the chain outbound                                     |
| `xray_xhttp_extra_settings`              |          | Extra xhttp padding/obfuscation settings                                  |
| `warp_outbound_enabled`                  |          | Enable Cloudflare WARP outbound                                           |
| `protonvpn_config_name`                  |          | Name of a `xray/protonvpn` entry to use as the ProtonVPN WireGuard outbound |
| `local_exit_rules`                       |          | List of raw xray routing rule objects injected before reverse/chain rules |

## Inventory groups reference

| Group          | Description                                                                 |
|----------------|-----------------------------------------------------------------------------|
| `xray`         | All xray hosts — full role is applied                                       |
| `xray_publish` | Hosts that serve subscription files via Caddy; publish scripts target these |
