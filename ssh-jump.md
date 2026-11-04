# SSH Jump Host — Operations Manual

## Overview

Reaches a tunnel-client host behind NAT, with no port forwarding, by hopping through a VPS with a
public IP. Targets today: `personal` (`personal-fedora-ai`, port 2222) and `work` (`work-asbx-neo`,
port 2223).

```
phone --ssh--> personal@<jump-host> --permitopen--> 127.0.0.1:2222 --> personal host:22
                      ^
     personal host --autossh--R--> tunnel-personal@<jump-host> (permitlisten 127.0.0.1:2222)

phone --ssh--> work@<jump-host> --permitopen--> 127.0.0.1:2223 --> work host:22
```

Each target host keeps an outbound reverse SSH tunnel to the VPS open at all times (works from
behind NAT, no router changes). Clients SSH into the VPS and are forwarded down that tunnel to the
target's real sshd.

Every target gets its own pair of restricted, single-purpose accounts on the VPS
(`ansible/roles/ssh_reverse_tunnel_user`, `ansible/roles/ssh_jump_user`): `nologin`, key-only, and
locked down in `authorized_keys` (`no-pty`, `no-agent-forwarding`, `no-X11-forwarding`, `no-user-rc`,
forced `command=`). A leaked key can do exactly one thing, for one target:

- **`tunnel-<name>`** — the target's tunnel-client host; may `permitlisten="127.0.0.1:<port>"`.
- **`<name>`** (e.g. `personal`, `work`) — client devices allowed to reach that target; may
  `permitopen="127.0.0.1:<port>"`. The account name doubles as the target, so
  `ssh -J personal@…` vs `ssh -J work@…` is unambiguous.

## Quick connect

```bash
# personal-fedora-ai
ssh -J personal@nl1.morjoff.com -p 2222 morjoff@127.0.0.1

# work-asbx-neo
ssh -J work@nl1.morjoff.com -p 2223 agent@127.0.0.1
```

Both use the same jump keypair (`~/.ssh/id_ed25519_jump`); the account/port pair, not the key,
selects the target. In a phone SSH app, add a "jump host"/"proxy" entry at
`nl1.morjoff.com:22` as user `personal` or `work`, then a target at `127.0.0.1:2222`/`:2223`
routed through it.

Each listener is loopback-only (no `GatewayPorts`), so none of these ports is reachable from the
internet directly — only via a second SSH hop through the matching account. The VPS still exposes
only port 22.

The jump host is the `ssh_jump` group in `ansible/inventory/xray.yml`, provisioned by
`ansible/xray.yml` (hostname, nftables, ssh_hardening, fail2ban); `ansible/ssh_jump.yml` layers the
restricted accounts on top, one pair per entry in `ssh_jump_targets` / `ssh_reverse_tunnel_targets`.

## One-time setup for a new target

### 1. Generate the target host's tunnel keypair

On the target host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/reverse_tunnel -N ""
```

Copy `~/.ssh/reverse_tunnel.pub` into the repo as
`ansible/roles/ssh_reverse_tunnel_user/files/<name>_reverse_tunnel.pub`, add an entry to
`ssh_reverse_tunnel_targets` (`ansible/roles/ssh_reverse_tunnel_user/defaults/main.yml`) with a new,
unused port, and a matching entry with the *same* port to `ssh_jump_targets`
(`ansible/roles/ssh_jump_user/defaults/main.yml`).

### 2. Trust client devices

Reuse the device `.pub` files in `ansible/files/devices/` (a device can be trusted for several
targets — that is a per-device decision, not a security requirement) or add a new one. List the
chosen keys under the new entry's `public_keys` in `ssh_jump_targets`.

### 3. Deploy the VPS side

```bash
./install-ssh-jump.sh
```

This rewrites every target's `authorized_keys` from the current config (`exclusive: true`), so run it
after **any** change to `ssh_jump_targets` or `ssh_reverse_tunnel_targets`, not only when adding a
target.

### 4. Add the host to the tunnel-client inventory

Add the host under `tunnel_clients` in `ansible/inventory/tunnel_clients.yml`, setting
`ssh_reverse_tunnel_client_remote_user` (`tunnel-<name>`) and
`ssh_reverse_tunnel_client_permitlisten` (`127.0.0.1:<port>`) to match step 1. Then:

```bash
./install-tunnel-client.sh
# or, only the new host:
./install-tunnel-client.sh --limit <inventory host name>
```

This installs `openssh-server`, `autossh` and `tmux`; enables sshd, disables password auth; templates
`/etc/systemd/system/ssh-tunnel.service` (an `autossh -N -R` unit pointed at `tunnel-<name>`,
`Restart=always`) and enables it; and adds a tmux auto-attach block to `~/.bashrc` (interactive logins
land in `tmux new -A -s main`). It refuses to run if `~/.ssh/reverse_tunnel` is missing rather than
generating an unregistered key.

### 5. Configure clients

Laptop `~/.ssh/config`:

```
Host jump-personal
    HostName <jump-host-domain>
    User personal
    IdentityFile ~/.ssh/id_ed25519_jump
    IdentitiesOnly yes

Host personal
    HostName 127.0.0.1
    Port 2222
    User <personal-host-ssh-user>
    ProxyJump jump-personal
    IdentityFile ~/.ssh/id_ed25519_personal

Host jump-work
    HostName <jump-host-domain>
    User work
    IdentityFile ~/.ssh/id_ed25519_jump
    IdentitiesOnly yes

Host work
    HostName 127.0.0.1
    Port 2223
    User agent
    ProxyJump jump-work
    IdentityFile ~/.ssh/id_ed25519_work
```

`ssh personal` / `ssh work` then does the whole hop. The same jump keypair can serve both entries;
isolation comes from the accounts and ports, not from different jump keys.

## Verification

```bash
# Restricted accounts refuse a shell/command (prints the restriction message, disconnects):
ssh tunnel-personal@<jump-host-domain>
ssh personal@<jump-host-domain>
ssh tunnel-work@<jump-host-domain>
ssh work@<jump-host-domain>

# On the VPS, once a tunnel is up:
ss -tlnp | grep -E '2222|2223'          # 127.0.0.1:<port> listening

# From a client device with a jump key (use -p; user@host:port is scp/sftp syntax):
ssh -J personal@<jump-host-domain> -p 2222 <personal-host-user>@127.0.0.1
ssh -J work@<jump-host-domain> -p 2223 agent@127.0.0.1

# Scoping: wrong ports are rejected with "administratively prohibited":
ssh -L 9999:127.0.0.1:22 personal@<jump-host-domain>
ssh -L 2222:127.0.0.1:2222 work@<jump-host-domain>     # work is permitopen 2223 only
```

## Revoking a device, rotating a tunnel key

Revoke a device: delete its `.pub` from `ansible/files/devices/` (if no other target uses it), remove
it from that target's `public_keys` in `ssh_jump_targets`, and re-run `./install-ssh-jump.sh`. Each
target's `authorized_keys` is rewritten every run, so the key stops working immediately for that
target; other targets that still list it are unaffected.

Rotate a target's tunnel key: repeat step 1, replace
`ansible/roles/ssh_reverse_tunnel_user/files/<name>_reverse_tunnel.pub`, re-run
`./install-ssh-jump.sh`, then update `~/.ssh/reverse_tunnel*` on the target and restart
`ssh-tunnel.service`.

## Inventory groups

| Group | Description |
|---|---|
| `ssh_jump` | Hosts that get the per-target `tunnel-<name>`/`<name>` accounts (`ansible/inventory/xray.yml`) |
| `tunnel_clients` | Tunnel-client hosts that get the `ssh_reverse_tunnel_client` role (`ansible/inventory/tunnel_clients.yml`) |
