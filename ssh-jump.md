# SSH Jump Host — Operations Manual

## Overview

Lets an SSH client anywhere (a phone, a laptop) reach a tunnel-client host that
sits behind NAT with no port-forwarding, by hopping through a VPS with a public
IP. Multiple independent tunnel-client hosts can share the same jump host —
today: `personal` (`personal-fedora-ai`) and `work` (`work-asbx-neo`).

```
phone --ssh--> personal@<jump-host> --permitopen--> 127.0.0.1:2222 --> personal host:22
                     ^
     personal host --autossh--R--> tunnel-personal@<jump-host> (permitlisten 127.0.0.1:2222)

phone --ssh--> work@<jump-host> --permitopen--> 127.0.0.1:2223 --> work host:22
                     ^
     work host --autossh--R--> tunnel-work@<jump-host> (permitlisten 127.0.0.1:2223)
```

Each tunnel-client host keeps an outbound reverse SSH tunnel open to the VPS at
all times (works from behind NAT, no router changes). Clients SSH into the VPS
and get forwarded down that tunnel to the tunnel-client host's real sshd.

Every target gets its own pair of restricted, single-purpose Linux accounts on
the VPS — see `ansible/roles/ssh_reverse_tunnel_user` and
`ansible/roles/ssh_jump_user`. All are `nologin`, key-only, and locked down via
`authorized_keys` options (`no-pty`, `no-agent-forwarding`, `no-X11-forwarding`,
`no-user-rc`, forced `command=`) so a leaked key can only do the one thing it's
scoped for — and because each target has its own account and its own port, a
leaked key for one target can never be used to reach another:

- **`tunnel-<name>`** — that target's tunnel-client host only. Its key may
  `permitlisten="127.0.0.1:<port>"` — open one loopback listener on the VPS.
  Nothing else.
- **`<name>`** (e.g. `personal`, `work`) — client devices (phone, spare
  laptop) allowed to reach that target. Their keys may
  `permitopen="127.0.0.1:<port>"` — forward a connection to that target's
  loopback listener. Nothing else. The account name doubles as which box it
  reaches, so `ssh -J personal@<jump-host> ...` vs `ssh -J work@<jump-host> ...`
  is unambiguous at a glance.

---

## Quick connect

```bash
# personal-fedora-ai
ssh -J personal@nl1.morjoff.com -p 2222 morjoff@127.0.0.1

# work-asbx-neo
ssh -J work@nl1.morjoff.com -p 2223 agent@127.0.0.1
```

Both use the same jump keypair (`~/.ssh/id_ed25519_jump`) — the account/port
pair, not the key, is what scopes which box you reach. Phone SSH app: a
"jump host" / "proxy" entry at `nl1.morjoff.com:22` as user `personal` or
`work`, then a target entry at `127.0.0.1:2222` (personal) or `127.0.0.1:2223`
(work) routed through that proxy.

Because each listener is loopback-only (not `GatewayPorts`), none of these
ports are ever reachable from the internet directly — only via a second SSH
hop through the matching `<name>` account. No firewall changes are needed; the
VPS still only exposes port 22.

The jump host is whichever xray host is listed under the `ssh_jump` group in
`ansible/inventory/xray.yml`. It's provisioned by `ansible/xray.yml` as usual
(hostname/nftables/ssh_hardening/fail2ban); `ansible/ssh_jump.yml` layers the
restricted accounts on top, one pair per entry in `ssh_jump_targets` /
`ssh_reverse_tunnel_targets`.

---

## One-time setup for a new target (e.g. adding a third tunneled host)

### 1. Generate the target host's tunnel keypair

On the target host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/reverse_tunnel -N ""
```

Copy the resulting `~/.ssh/reverse_tunnel.pub` into this repo as
`ansible/roles/ssh_reverse_tunnel_user/files/<name>_reverse_tunnel.pub`, and add
an entry for it to `ssh_reverse_tunnel_targets`
(`ansible/roles/ssh_reverse_tunnel_user/defaults/main.yml`) with a new,
unused port. Add a matching entry to `ssh_jump_targets`
(`ansible/roles/ssh_jump_user/defaults/main.yml`) with the *same* port.

### 2. Trust client devices for the new target

Reuse the existing device `.pub` files in `ansible/files/devices/` (a phone or
laptop already trusted for another target can be trusted for this one too —
that's a per-device decision, not a security requirement), or add a new one
per device. List whichever ones should be able to reach this target under the
new entry's `public_keys` in `ssh_jump_targets`.

### 3. Deploy the VPS side

```bash
./install-ssh-jump.sh
```

This rewrites every target's `authorized_keys` from its current config
(`exclusive: true`), so run it after *any* change to `ssh_jump_targets` or
`ssh_reverse_tunnel_targets` — not just when adding a target.

### 4. Add the host to the tunnel-client inventory

Add the host to `ansible/inventory/tunnel_clients.yml` under `tunnel_clients`,
overriding `ssh_reverse_tunnel_client_remote_user` (`tunnel-<name>`) and
`ssh_reverse_tunnel_client_permitlisten` (`127.0.0.1:<port>`) to match what you
registered in step 1. Then deploy:

```bash
./install-tunnel-client.sh
# or, to touch only the new host:
./install-tunnel-client.sh --limit <inventory host name>
```

This installs `openssh-server`, `autossh`, and `tmux`; enables sshd and
disables password auth; templates `/etc/systemd/system/ssh-tunnel.service` (an
`autossh -N -R` unit pointed at the `tunnel-<name>` account, `Restart=always`)
and enables it; and adds a tmux auto-attach block to `~/.bashrc` so any
interactive SSH login lands in a persistent `tmux new -A -s main` session (see
`ansible/roles/ssh_reverse_tunnel_client`). It refuses to run if
`~/.ssh/reverse_tunnel` (the identity file from step 1) is missing rather than
generating a new, unregistered keypair.

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

Then `ssh personal` or `ssh work` does the whole hop. (The same jump keypair
can be reused for both `jump-personal` and `jump-work` `User` entries if the
same device should reach both — the target-side isolation comes from the
separate accounts/ports, not from using different jump keys.)

Phone SSH app (Termius, JuiceSSH, etc.): create a "jump host" / "proxy" entry
pointing at `<jump-host-domain>` as user `personal` (or `work`) with the
phone's jump key, then a target host entry at `127.0.0.1:2222` (or `:2223`)
routed through that proxy, using whatever key/password the target host's real
sshd expects.

---

## Verification

```bash
# From anywhere: restricted accounts refuse a shell/command
ssh tunnel-personal@<jump-host-domain>   # prints the restriction message, disconnects
ssh personal@<jump-host-domain>          # same
ssh tunnel-work@<jump-host-domain>       # same
ssh work@<jump-host-domain>              # same

# On the VPS, once a tunnel-client host's tunnel is up:
ss -tlnp | grep -E '2222|2223'          # 127.0.0.1:<port> listening

# From a client device with a jump key:
# (user@host:port isn't valid ssh syntax — that's scp/sftp form. Use -p.)
ssh -J personal@<jump-host-domain> -p 2222 <personal-host-user>@127.0.0.1
ssh -J work@<jump-host-domain> -p 2223 agent@127.0.0.1

# Confirm scoping — wrong port is rejected:
ssh -L 9999:127.0.0.1:22 personal@<jump-host-domain>   # "administratively prohibited"
ssh -L 2222:127.0.0.1:2222 work@<jump-host-domain>     # "administratively prohibited" (work is only permitopen 2223)
```

---

## Revoking a device

Delete its `.pub` file from `ansible/files/devices/` (if unused by any other
target) and remove the corresponding entry from that target's `public_keys` in
`ssh_jump_targets` (`ansible/roles/ssh_jump_user/defaults/main.yml`), then
re-run `./install-ssh-jump.sh`. Each target account's `authorized_keys` is
rewritten every run, so the old key stops working immediately for that target
(other targets it's still listed under are unaffected).

To rotate a target host's tunnel key: repeat step 1 with a new keypair,
replace `ansible/roles/ssh_reverse_tunnel_user/files/<name>_reverse_tunnel.pub`,
re-run `./install-ssh-jump.sh`, then update `~/.ssh/reverse_tunnel*` on that
target host and restart `ssh-tunnel.service`.

---

## Inventory groups reference

| Group            | Description                                                                              |
|------------------|-------------------------------------------------------------------------------------------|
| `ssh_jump`       | Hosts that get the per-target `tunnel-<name>`/`<name>` restricted accounts (`ansible/inventory/xray.yml`) |
| `tunnel_clients` | Tunnel-client hosts that get the `ssh_reverse_tunnel_client` role (`ansible/inventory/tunnel_clients.yml`) |
