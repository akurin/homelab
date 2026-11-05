# Xray VPN — Operations Manual

## Overview

A chain of Xray VLESS/XHTTP proxy servers managed by Ansible. Servers are deployed from the local
machine; client configs are generated locally and published to a Caddy-hosted subscription URL.

```
Client → ru-ruvds → dk-webdock → internet
                  ↘ (direct) → Russian sites (.ru)
```

- `nl-vdsina` is a standalone server (no chain).
- `dk-webdock` and `nl-vdsina` are **exit nodes**. On `dk-webdock`, OpenAI/Anthropic/AWS use
  Oxylabs, Google uses the server's own IP, and other traffic uses WARP. `nl-vdsina` keeps its
  direct exceptions with WARP as its default.
- `ru-ruvds` is also the **publish server**: subscription JSON under
  `https://<domain>/subscriptions/<token>`. Hosts in `xray_publish` are publish targets.
- No machine runs a local Xray **client** any more: x13's loopback SOCKS client was removed with the
  K3s overlay migration, and the K3s cluster does not use Xray at all.

## Prerequisites

`ansible`, `pass` (GPG password manager), `python3` (stdlib only), `jq`.

## Secret store (`pass xray/`)

| Key | Contents |
|---|---|
| `xray/uuids` | JSON array of all users |
| `xray/subscriptions` | JSON array of named subscriptions |
| `xray/protonvpn` | JSON array of named ProtonVPN WireGuard configs |
| `xray/outbounds` | JSON array of named raw Xray outbounds |

### User record (`xray/uuids`)

```json
[
  { "name": "xray_client", "id": "<uuid>", "skip_client_config": true },
  { "name": "morjoff", "id": "<uuid>", "configs": [{ "name": "full_proxy" }] },
  {
    "name": "olga",
    "id": "<uuid>",
    "configs": [
      {
        "name": "selective",
        "routing_rules": [
          { "type": "field", "domain": ["geosite:youtube", "geosite:google"], "balancerTag": "balancer" },
          { "type": "field", "network": "tcp,udp", "outboundTag": "direct" }
        ]
      }
    ]
  }
]
```

`xray_client` is the server-to-server chaining identity — always `skip_client_config: true`.
Each named config generates one LB client config file; its `routing_rules` are injected after the
fixed infrastructure rules (`bittorrent→direct`, `socks_direct→direct`).

| Outbound tag | Description |
|---|---|
| `balancer` | Load-balanced proxy (`proxy_direct` preferred, `proxy_cdn` fallback) |
| `proxy_direct` | Direct connection to the server, bypassing the balancer |
| `direct` | Local internet, no proxy |

### Subscription record (`xray/subscriptions`)

```json
[
  {
    "name": "morjoff_vpn",
    "token": "<uuid>",
    "files": [
      { "path": "~/vpn/morjoff/ru-ruvds_lb_full_proxy_config.json" },
      { "path": "~/vpn/morjoff/ru-ruvds_lb_full_proxy_config.json", "remark": "Custom name" }
    ]
  }
]
```

`token` is the unguessable URL segment: `uuidgen | tr '[:upper:]' '[:lower:]'`. `files` accepts glob
patterns and an optional per-entry `remark`.

### ProtonVPN record (`xray/protonvpn`)

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

Values come from the WireGuard `.conf` ProtonVPN issues for a device. `address` is a JSON array —
split the comma-separated `Interface Address` line into one entry per item. `allowed_ips` (default
`["0.0.0.0/0", "::/0"]`) and `persistent_keepalive` (default `25`) can be overridden per entry.

A ProtonVPN config is tied to one device, so one entry per server that needs it, each generated as a
separate device in the ProtonVPN dashboard.

### Named outbound record (`xray/outbounds`)

A reusable name for a raw Xray outbound; the value is written to the server config unchanged, so any
protocol works. Keep it in `pass` — it usually contains credentials.

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

The `tag` must be unique and must not be one of `next_proxy`, `warp`, `protonvpn`, `direct`, `block`.
`targetStrategy: AsIs` preserves the destination as received (IP stays IP, hostname stays hostname);
the tested Oxylabs endpoint accepted hostnames and IPv4 addresses but rejected IPv6 addresses. For an
IPv4-only exit, have the client resolve first:

```yaml
xray_client:
  dns_query_strategy: UseIPv4
  target_strategy: ForceIPv4
```

Xray uses SOCKS5 `UDP ASSOCIATE` automatically for UDP to this outbound (there is no `udp: true`
setting); UDP must be enabled on the Oxylabs account itself.

## Generated client configs

For each user × host, Ansible writes JSON under `~/vpn/<user>/`:

| File | Remark | Description |
|---|---|---|
| `<host>_<config>_config.json` | `user@host · Config` | Direct connection |
| `<host>_lb_<config>_config.json` | `user@host · Config · LB` | Load-balanced: `proxy_direct` preferred, CDN fallback (needs `cdn_domain` + `server_ip`) |

LB configs use `burstObservatory` (3 samples/minute) and `fallbackTag` to switch to the CDN outbound
when `proxy_direct` is dead.

## Scripts

### `./install-xray.sh [ansible args…]`

Full deploy: installs Xray on all servers, generates client configs, merges subscriptions and
uploads them to the publish server. Arguments pass through to every `ansible-playbook` invocation.

```bash
./install-xray.sh
./install-xray.sh --limit ru-ruvds
```

### `./publish-xray-client-configs.sh [ansible args…]`

Config-only update: regenerate, merge, republish and reload Caddy, without redeploying servers. Use
after changing `xray/uuids` or `xray/subscriptions`.

```bash
./publish-xray-client-configs.sh
./publish-xray-client-configs.sh --limit ru-ruvds
```

Stages: **generate** (`~/vpn/<user>/`) → **merge** (`scripts/merge-subscriptions.py`, with remark
overrides) → **publish** (`/var/www/xray-configs/<token>/` on the publish server, stale token
directories removed) → **Caddy reload** (`publish-xray-client-configs.sh` only; `install-xray.sh`
also deploys Xray and Caddy first).

### Scoped deploys

Every role in `ansible/xray.yml` is tagged with its name (`hostname`, `nftables`, `grafana_alloy`,
`freedns`, `xray`, `caddy_proxy`, `ssh_hardening`, `ssh_alert`, `xray_publish`). Handlers ignore
tags, so a restart still fires.

```bash
cd ansible
ansible-playbook xray.yml -i inventory/xray.yml \
  --limit xray_exit --tags xray \
  -e xray_users_b64="$(pass xray/uuids | base64)" \
  -e protonvpn_configs_b64="$( (pass xray/protonvpn 2>/dev/null || echo '[]') | base64)" \
  -e xray_outbounds_b64="$( (pass xray/outbounds 2>/dev/null || echo '[]') | base64)"
```

`--check --diff` previews; `--list-tags` / `--list-tasks --tags xray` shows what would run;
`--skip-tags client_configs` suppresses the local client-config render.

## Subscription URLs

After publishing, Ansible prints them:

```
https://clumsypanda.mooo.com/subscriptions/<token>
```

Import into an Xray client (v2rayN, NekoBox, …).

## Common operations

**Add a user:** edit `xray/uuids` (fresh UUID), add the user's files to the relevant subscription in
`xray/subscriptions`, run `./install-xray.sh`.

**Add a subscription:** generate a token (`uuidgen | tr '[:upper:]' '[:lower:]'`), add the entry to
`xray/subscriptions`, run `./publish-xray-client-configs.sh` (directories are created automatically).

**Change a user's routing:** edit `configs` in `xray/uuids`, run
`./publish-xray-client-configs.sh`.

**Add a server:** add it to `ansible/inventory/xray.yml` (`domain`, `ansible_host`, optionally
`cdn_domain`/`server_ip`, `next_address`, `xray_xhttp_extra_settings`, `xray_routing_rules`,
`xray_outbounds`, `xray_client`), run `./install-xray.sh <new_host>`, add its configs to the
subscriptions, run `./publish-xray-client-configs.sh`.

**Switch an exit to ProtonVPN:** add an entry to `xray/protonvpn` with a device dedicated to that
server, select it in the host vars, deploy that host:

```yaml
xray_outbounds:
  - type: protonvpn
    config: <entry name>
```

**Switch an exit to a named outbound:** add the record to `xray/outbounds`, select it, deploy:

```yaml
xray_outbounds:
  - type: named
    name: oxylabs
```

A server with `next_address` uses that hop as its default egress; otherwise the first `xray_outbounds`
entry is the default, and an empty list means `direct` (its own IP). Multiple entries are allowed:
the first is the default, the rest are available to routing rules by tag. Types: `direct`, `block`,
`warp`, `protonvpn`, `named`.

**Route domains on exit servers:** hosts in `xray_exit` (`dk-webdock`, `nl-vdsina`) send Google
domains and IP ranges to `direct`; host-specific rules choose other egresses.

```yaml
xray_exit:
  hosts:
    dk-webdock:
    nl-vdsina:
  vars:
    xray_routing_rules:
      - type: field
        domain: ["geosite:google"]
        outboundTag: direct
      # IP-only flows (Meet/WebRTC media) carry no SNI
      - type: field
        ip: ["geoip:google"]
        outboundTag: direct

dk-webdock:
  xray_additional_routing_rules:
    - type: field
      domain: *xray_alternate_egress_domains
      outboundTag: oxylabs
```

`xray_routing_rules` accepts raw rules with any outbound tag; `xray_additional_routing_rules`
appends host-specific rules. Both are rendered after the built-in DNS/BitTorrent rules and before
reverse/chain rules, so first match wins; deployment fails if an `outboundTag` does not exist on the
host. `domain:` entries cover subdomains and match through SNI even when the client connects by IP.
Google needs both forms: `geosite:google` (domains, incl. ccTLDs) and `geoip:google` (IP-only flows);
referencing a `geosite:` category makes the role fetch `geosite.dat` (~74 MB), `geoip.dat` is always
present.

Server-sniffed BitTorrent is always blocked: ProtonVPN free servers forbid P2P, and exiting P2P from
the VPS IP invites abuse complaints. Clients send detectable BitTorrent `direct` themselves.

## Inventory host vars

| Variable | Required | Description |
|---|---|---|
| `domain` | ✓ | Public domain, used for TLS and Caddy |
| `dns` | ✓ | `freedns` (auto-updated via role) or `external` (manual) |
| `cdn_domain` | | CDN domain for SNI in CDN/LB client configs |
| `server_ip` | | Real IP behind the CDN (enables CDN config generation) |
| `next_address` | | Next hop domain for server chaining |
| `next_address_xray_xhttp_extra_settings` | | XHTTP settings for the chain outbound |
| `xray_xhttp_extra_settings` | | Extra XHTTP padding/obfuscation settings |
| `xray_outbounds` | | Ordered outbound selections; first is default unless `next_address` is set |
| `xray_client` | | Generated-client options (`dns_query_strategy`, `target_strategy`) |
| `xray_routing_rules` | | Raw server rules, after built-ins and before reverse/chain rules |
| `xray_additional_routing_rules` | | Host-specific rules appended to common/group rules |
| `xray_geodata_release` | | runetfreedom geo data release path (default: latest) |

## Inventory groups

| Group | Description |
|---|---|
| `xray` | All Xray hosts — full role applied |
| `xray_publish` | Hosts serving subscription files via Caddy; publish scripts target these |
| `xray_exit` | Exit nodes with common Google-direct routing rules |
