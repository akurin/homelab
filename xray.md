# Xray VPN — Operations Manual

## Overview

A chain of xray VLESS/xhttp proxy servers managed via Ansible. Servers are deployed
and configured from a local machine; client configs are generated locally and
published to a Caddy-hosted subscription URL.

```
Client → ru-ruvds → dk-webdock → internet
                  ↘ (direct) → Russian sites (.ru)
```

`nl-vdsina` is a standalone server (no chain).

`dk-webdock` and `nl-vdsina` are **exit nodes**. On `dk-webdock`, OpenAI,
Anthropic and AWS use Oxylabs, Google uses the server's own IP, and other
traffic uses WARP. `nl-vdsina` keeps its existing direct exceptions with WARP
as its default (see
[Route domains directly on the exit servers](#route-domains-directly-on-the-exit-servers)).

`ru-ruvds` is also the **publish server** — it hosts subscription JSON files via
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
| `xray/subscriptions` | JSON array of named subscriptions (see below) |
| `xray/protonvpn`     | JSON array of named ProtonVPN WireGuard configs (see below) |
| `xray/outbounds`     | JSON array of named raw Xray outbounds (see below) |

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
    "configs": [
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
        "path": "~/vpn/morjoff/ru-ruvds_lb_full_proxy_config.json"
      },
      {
        "path": "~/vpn/morjoff/ru-ruvds_lb_full_proxy_config.json",
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

### Generic outbound record (`xray/outbounds`)

Each record gives a reusable name to a raw Xray outbound. The `outbound` value is
written to the server config unchanged, so this mechanism works with any outbound
protocol Xray supports. Keep this file in `pass` because it normally contains
credentials.

For the tested Oxylabs ISP SOCKS5 endpoint, split the value passed to curl's
`-U` option at the first `:` into `user` and `pass`:

```json
[
  {
    "name": "oxylabs",
    "outbound": {
      "tag": "oxylabs",
      "protocol": "socks",
      "targetStrategy": "AsIs",
      "settings": {
        "address": "isp.oxylabs.io",
        "port": 8001,
        "user": "<value before colon>",
        "pass": "<value after colon>"
      }
    }
  }
]
```

The outbound `tag` must be unique and cannot be one of the built-in tags:
`next_proxy`, `warp`, `protonvpn`, `direct`, or `block`. Xray's
[SOCKS outbound](https://xtls.github.io/en/config/outbounds/socks.html) supports
SOCKS5 and uses the flat `address`, `port`, `user`, and `pass` settings shown
above.

`targetStrategy: AsIs` preserves the destination received by the server: an IP
remains an IP and a hostname remains a hostname. The tested Oxylabs endpoint
accepted both hostname and IPv4-address requests, but rejected IPv6-address
requests.

Clients can still send an IP address even with `targetStrategy: AsIs`. For an
IPv4-only server exit, configure the generated client to resolve proxied targets
before sending them through VLESS:

```yaml
xray_client:
  dns_query_strategy: UseIPv4
  target_strategy: ForceIPv4
```

This keeps server-side sniffing at `routeOnly: true`: a sniffed hostname can be
used for routing, but does not replace the client's destination. Both hostname
and IPv4-address SOCKS requests to the tested Oxylabs endpoint completed 10/10
Cloudflare Speed Test connections; IPv6-address requests were rejected.

Xray automatically uses SOCKS5 `UDP ASSOCIATE` when it routes UDP traffic to
this outbound; there is no outbound `udp: true` setting to add. UDP still has to
be enabled for the specific Oxylabs account and endpoint. Oxylabs advertises
[UDP-capable proxies](https://oxylabs.io/products/udp-proxies), but currently
notes on that page that UDP is not supported for self-service clients. The curl
command above tests the SOCKS5 endpoint over TCP only, so test UDP separately if
the account is expected to include it.

---

## Generated client configs

For each user × host, Ansible generates local JSON files under `~/vpn/<user>/`:

| File                             | Remark                       | Description                                                                          |
|----------------------------------|------------------------------|--------------------------------------------------------------------------------------|
| `<host>_<config>_config.json`    | `user@host · Config`         | Direct connection                                                                    |
| `<host>_lb_<config>_config.json` | `user@host · Config · LB`    | Load-balanced: `proxy_direct` preferred, CDN fallback (needs `cdn_domain` + `server_ip`) |

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
./install-xray.sh --limit ru-ruvds      # single host
```

### `./publish-xray-client-configs.sh [ansible-playbook args...]`

Lightweight update: regenerates client configs and re-publishes subscriptions.
Use this after changing `xray/uuids` or `xray/subscriptions` without needing
to redeploy the servers. Arguments are passed straight through to every
`ansible-playbook` invocation in the script.

```bash
./publish-xray-client-configs.sh
./publish-xray-client-configs.sh --limit ru-ruvds
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

### Scoped deploys

Every role in `ansible/xray.yml` is tagged with its role name
(`hostname`, `nftables`, `grafana_alloy`, `freedns`, `xray`, `caddy_proxy`,
`ssh_hardening`, `ssh_alert`, `xray_publish`). Combine `--limit` and `--tags`
to re-render and restart only Xray without touching the rest:

```bash
cd ansible
ansible-playbook xray.yml -i inventory/xray.yml \
  --limit xray_exit --tags xray \
  -e xray_users_b64="$(pass xray/uuids | base64)" \
  -e protonvpn_configs_b64="$( (pass xray/protonvpn 2>/dev/null || echo '[]') | base64)" \
  -e xray_outbounds_b64="$( (pass xray/outbounds 2>/dev/null || echo '[]') | base64)"
```

Handlers ignore tags, so the Xray restart still fires. Add `--check --diff` to
preview, or `--list-tags` / `--list-tasks --tags xray` to see what would run.
`--skip-tags client_configs` also suppresses the local client-config render.

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

1. `pass edit xray/uuids` — update `configs` for the user
2. `./publish-xray-client-configs.sh` — regenerate and republish

### Add a new server

1. Add host to `ansible/inventory/xray.yml` with `domain`, `ansible_host`, and
   optionally `cdn_domain`/`server_ip`, `next_address`, `xray_xhttp_extra_settings`,
   `xray_routing_rules`, `xray_outbounds`, and `xray_client`
2. `./install-xray.sh <new_host>`
3. Add the new host's config files to subscriptions as needed
4. `./publish-xray-client-configs.sh`

### Switch a server's exit to ProtonVPN

1. `pass edit xray/protonvpn` — add an entry with the WireGuard config values for
   a device dedicated to this server (see [ProtonVPN config
   record](#protonvpn-config-record-xrayprotonvpn))
2. Select it on the host in `ansible/inventory/xray.yml`:

   ```yaml
   xray_outbounds:
     - type: protonvpn
       config: <entry name>
   ```

3. `./install-xray.sh --limit <host>`

A server that has `next_address` uses its next hop as the default egress.
Otherwise, the first entry in `xray_outbounds` is the default. With an empty
list, the server uses its own IP through `direct`.

WARP uses the same interface:

```yaml
xray_outbounds:
  - type: warp
```

### Switch a server's exit to a named outbound

1. `pass edit xray/outbounds` — add the named raw Xray outbound record.
2. Select it on the host in `ansible/inventory/xray.yml`:

   ```yaml
   xray_outbounds:
     - type: named
       name: oxylabs
   ```

3. `./install-xray.sh --limit <host> --tags xray`

Multiple entries may be selected. The first is the default egress and the
others are available to `xray_routing_rules` by tag. The supported types are
`direct`, `block`, `warp`, `protonvpn`, and `named`.

For example, `dk-webdock` uses WARP by default while making Oxylabs available
to routing rules:

```yaml
xray_outbounds:
  - type: warp
  - type: named
    name: oxylabs
```

### Route domains directly on the exit servers

Hosts in the `xray_exit` group (`dk-webdock`, `nl-vdsina`) send Google domains
and IP ranges to `direct`. Host-specific rules select different egresses for
OpenAI, Anthropic, and AWS while everything else uses the first configured
outbound.

```yaml
    xray_exit:
      hosts:
        dk-webdock:
        nl-vdsina:
      vars:
        xray_routing_rules:
          - type: field
            domain:
              - "geosite:google"
              # ...
            outboundTag: direct
          # IP-only flows (Meet/WebRTC media) never carry an SNI
          - type: field
            ip:
              - "geoip:google"
            outboundTag: direct

    dk-webdock:
      xray_additional_routing_rules:
        - type: field
          domain: *xray_alternate_egress_domains
          outboundTag: oxylabs
```

`xray_routing_rules` accepts raw Xray routing rules with any outbound tag
(`direct`, `block`, `next_proxy`, `warp`, `protonvpn`, or a named outbound's
tag). `xray_additional_routing_rules` appends host-specific rules to common/group
rules. Rules are rendered after the built-in DNS/bittorrent rules and before
reverse/chain rules, so first match wins. Deployment fails if an `outboundTag`
does not exist on that host. `domain:` entries also cover all subdomains, and
SNI sniffing means they match even when a client connects by IP.

Google needs both forms: `geosite:google` matches the domain list (including
ccTLDs), while `geoip:google` catches IP-only flows such as Google Meet/WebRTC
media. Referencing a `geosite:` category also makes the role fetch
`geosite.dat` (~74 MB) on those hosts; `geoip.dat` is always present.

BitTorrent traffic sniffed on a server is always blocked: ProtonVPN free servers
forbid P2P, and exiting it from the VPS IP invites abuse complaints. Clients
send detectable BitTorrent `direct` themselves.

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
| `xray_outbounds`                         |          | Ordered outbound selections; first is default unless `next_address` is set |
| `xray_client`                            |          | Generated-client options such as `dns_query_strategy` and `target_strategy` |
| `xray_routing_rules`                     |          | Raw server routing rules injected after built-in rules, before reverse/chain rules |
| `xray_additional_routing_rules`          |          | Host-specific rules appended to common/group routing rules                |
| `xray_geodata_release`                   |          | runetfreedom geo data release path, e.g. `download/202610121114` (default: latest) |

## Inventory groups reference

| Group          | Description                                                                 |
|----------------|-----------------------------------------------------------------------------|
| `xray`         | All xray hosts — full role is applied                                       |
| `xray_publish` | Hosts that serve subscription files via Caddy; publish scripts target these |
| `xray_exit`    | Exit nodes with common Google-direct routing rules                          |
