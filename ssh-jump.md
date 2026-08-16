# SSH Jump Host — Operations Manual

## Overview

Lets an SSH client anywhere (a phone, a laptop) reach a home host that sits behind
NAT with no port-forwarding, by hopping through a VPS with a public IP.

```
phone --ssh--> jump@<jump-host> --permitopen--> 127.0.0.1:2222 --> home host:22
                     ^
home host --autossh--R--> tunnel@<jump-host> (permitlisten 127.0.0.1:2222)
```

The home host keeps an outbound reverse SSH tunnel open to the VPS at all times
(works from behind NAT, no router changes). Clients SSH into the VPS and get
forwarded down that tunnel to the home host's real sshd.

Two restricted, single-purpose Linux accounts live on the VPS — see
`ansible/roles/ssh_reverse_tunnel_user` and `ansible/roles/ssh_jump_user`. Both are
`nologin`, key-only, and locked down via `authorized_keys` options
(`no-pty`, `no-agent-forwarding`, `no-X11-forwarding`, `no-user-rc`, forced
`command=`) so a leaked key can only do the one thing it's scoped for:

- **`tunnel`** — home host only. Its key may `permitlisten="127.0.0.1:2222"` — open
  one loopback listener on the VPS. Nothing else.
- **`jump`** — client devices (phone, spare laptop). Its keys may
  `permitopen="127.0.0.1:2222"` — forward a connection to that same loopback
  listener. Nothing else.

Because the listener is loopback-only (not `GatewayPorts`), port 2222 is never
reachable from the internet directly — only via a second SSH hop through `jump`.
No firewall changes are needed; the VPS still only exposes port 22.

The jump host is whichever xray host is listed under the `ssh_jump` group in
`ansible/inventory/xray.yml`. It's provisioned by `ansible/xray.yml` as usual
(hostname/nftables/ssh_hardening/fail2ban); `ansible/ssh_jump.yml` layers the two
restricted accounts on top.

---

## One-time setup

### 1. Generate the home host's tunnel keypair

On the home host:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/reverse_tunnel -N ""
```

Copy the resulting `~/.ssh/reverse_tunnel.pub` into this repo as
`ansible/roles/ssh_reverse_tunnel_user/files/ssh_reverse_tunnel_user.pub`.

### 2. Generate a jump keypair per client device

On your workstation (or directly on the phone if the SSH app supports key
generation):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_jump -N ""
```

Copy the `.pub` into this repo, e.g.
`ansible/roles/ssh_jump_user/files/phone.pub`, and list it in
`ssh_jump_user_public_keys` (`ansible/roles/ssh_jump_user/defaults/main.yml`). Add
one file + list entry per additional device.

### 3. Deploy the VPS side

```bash
./install-ssh-jump.sh
```

### 4. Install the reverse tunnel on the home host

Add the host to `ansible/inventory/home.yml` under the `home` group, then deploy
the `ssh_reverse_tunnel_client` role:

```bash
./install-home-tunnel.sh
```

This installs `openssh-server`, `autossh`, and `tmux`; enables sshd and disables
password auth; templates `/etc/systemd/system/ssh-tunnel.service` (an
`autossh -N -R` unit pointed at the `tunnel` account, `Restart=always`) and
enables it; and adds a tmux auto-attach block to `~/.bashrc` so any interactive
SSH login lands in a persistent `tmux new -A -s main` session (see
`ansible/roles/ssh_reverse_tunnel_client`). It refuses to run if
`~/.ssh/reverse_tunnel` (the identity file from step 1) is missing rather than
generating a new, unregistered keypair.

### 5. Configure clients

Laptop `~/.ssh/config`:

```
Host jump
    HostName <jump-host-domain>
    User jump
    IdentityFile ~/.ssh/id_ed25519_jump
    IdentitiesOnly yes

Host home
    HostName 127.0.0.1
    Port 2222
    User <home-ssh-user>
    ProxyJump jump
    IdentityFile ~/.ssh/id_ed25519_home
```

Then `ssh home` does the whole hop.

Phone SSH app (Termius, JuiceSSH, etc.): create a "jump host" / "proxy" entry
pointing at `<jump-host-domain>` as user `jump` with the phone's private jump key,
then a "home" host entry at `127.0.0.1:2222` routed through that proxy, using
whatever key/password the home host's real sshd expects.

---

## Verification

```bash
# From anywhere: restricted accounts refuse a shell/command
ssh tunnel@<jump-host-domain>   # prints the restriction message, disconnects
ssh jump@<jump-host-domain>     # same

# On the VPS, once the home host's tunnel is up:
ss -tlnp | grep 2222            # 127.0.0.1:2222 listening

# From a client device with a jump key:
# (user@host:port isn't valid ssh syntax — that's scp/sftp form. Use -p.)
ssh -J jump@<jump-host-domain> -p 2222 <home-user>@127.0.0.1

# Confirm scoping — wrong port is rejected:
ssh -L 9999:127.0.0.1:22 jump@<jump-host-domain>   # "administratively prohibited"
```

---

## Revoking a device

Delete its `.pub` file from `ansible/roles/ssh_jump_user/files/` and remove the
corresponding entry from `ssh_jump_user_public_keys`, then re-run
`./install-ssh-jump.sh`. The whole `jump` account's `authorized_keys` is rewritten
each run, so the old key stops working immediately.

To rotate the home host's tunnel key: repeat step 1 with a new keypair, replace
`ansible/roles/ssh_reverse_tunnel_user/files/ssh_reverse_tunnel_user.pub`, re-run
`./install-ssh-jump.sh`, then update `~/.ssh/reverse_tunnel*` on the home host
and restart `ssh-tunnel.service`.

---

## Inventory groups reference

| Group      | Description                                                          |
|------------|------------------------------------------------------------------------|
| `ssh_jump` | Hosts that get the `tunnel`/`jump` restricted accounts (`ansible/inventory/xray.yml`) |
| `home`     | Home hosts that get the `ssh_reverse_tunnel_client` role (`ansible/inventory/home.yml`) |
