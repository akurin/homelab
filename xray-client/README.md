# Xray Proxy Client Setup with TProxy

This guide explains how to set up and run an Xray proxy client with transparent proxy (TProxy) support on Linux.

## Overview

The setup uses:

- **Xray** as the proxy client with VLESS protocol over XHTTP transport
- **TProxy** for transparent proxying of all system traffic
- **nftables** for packet routing and marking
- **Dedicated xray user** for security isolation

## Prerequisites

- Linux system with root access
- `nftables` installed
- `iproute2` package installed
- Xray binary downloaded to `/opt/Xray-linux-64/xray`
- Configuration file ready (e.g., `~/vpn/xray_xhttp_client_config.json`)

## Installation Steps

### 1. Create Dedicated Xray User

Create a system user for running Xray without login privileges:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin --user-group xray
```

This creates a dedicated user that:

- Has no home directory
- Cannot log in interactively
- Runs with minimal privileges

### 2. Grant Network Capabilities

Grant the Xray binary necessary network capabilities:

```bash
sudo setcap 'cap_net_admin,cap_net_bind_service+ep' /opt/Xray-linux-64/xray
```

**What this does:**

- `cap_net_admin` - Allows network administration operations (routing, firewall rules)
- `cap_net_bind_service` - Required for socket binding operations (even though we don't use privileged ports, Xray needs
  this to avoid "socket bind: permission denied" errors)
- `+ep` - Effective and permitted flags make these capabilities active

This allows Xray to perform network operations without running as root.

### 3. Prepare TProxy Scripts

Ensure you have the following files in your working directory (e.g., `~/xray-client/`):

- `xray_tproxy.sh` - Script to enable/disable TProxy routing
- `xray_tproxy.nft` - nftables rules for packet interception

## Configuration

### Client Configuration

The client config (`xray_xhttp_client_config.json`) includes:

**Inbounds:**

- Port `12345` - TProxy inbound (dokodemo-door) for intercepted traffic
- Port `1080` - SOCKS5 proxy on localhost for manual use

**Outbounds:**

- VLESS protocol over XHTTP transport with TLS
- Direct routing for DNS servers (1.1.1.1, 8.8.8.8)
- Direct routing for `.ru` domains (bypass proxy)

**DNS:**

- Uses DNS-over-HTTPS (DoH) to Cloudflare and Google

### TProxy Configuration

The TProxy setup uses:

- **Mark:** `0x1` for tagged packets
- **Routing table:** `100` for TProxy routes
- **TProxy port:** `12345` (matches Xray inbound)

**Traffic routing:**

- DNS queries (port 53) are intercepted and proxied
- Private IP ranges are bypassed (10.0.0.0/8, 192.168.0.0/16, etc.)
- Public IPv4/IPv6 traffic is proxied
- Traffic from the `xray` user bypasses TProxy (prevents loops)

## Usage

### Starting the Proxy

**Step 1:** Enable TProxy routing (requires root):

```bash
cd ~/xray-client
sudo ./xray_tproxy.sh on
```

This will:

- Create routing rules with fwmark `0x1` → table `100`
- Add local default routes via loopback
- Load nftables rules for packet interception

**Step 2:** Start Xray client (as xray user):

```bash
sudo -u xray xray -c ~/vpn/xray_xhttp_client_config.json
```

Or with custom binary path:

```bash
cat ~/vpn/xray_xhttp_client_config.json | sudo -u xray xray
```

### Stopping the Proxy

**Step 1:** Stop the Xray process:

```bash
# Press Ctrl+C in the terminal running Xray
# Or kill the process:
sudo pkill -u xray xray
```

**Step 2:** Disable TProxy routing:

```bash
cd ~/xray-client
sudo ./xray_tproxy.sh off
```

This will:

- Remove routing rules and flush table `100`
- Delete nftables tables `xray_tproxy` and `xray_tproxy_local`

## Verification

### Check TProxy Status

```bash
# Check routing rules
ip rule show | grep 100
ip -6 rule show | grep 100

# Check nftables rules
sudo nft list tables
sudo nft list table inet xray_tproxy
sudo nft list table inet xray_tproxy_local
```

### Check Xray Status

```bash
# Check if Xray is running
ps aux | grep xray

# Check Xray logs (if running in foreground)
# Look for connection status and any errors
```

### Test Connectivity

```bash
# Test your public IP (should show proxy server IP)
curl ifconfig.me

# Test DNS resolution
nslookup google.com

# Test SOCKS5 proxy directly
curl --socks5 127.0.0.1:1080 ifconfig.me
```

## Troubleshooting

### TProxy Not Working

1. Verify nftables rules are loaded:
   ```bash
   sudo nft list ruleset | grep xray
   ```

2. Check routing rules exist:
   ```bash
   ip rule show | grep 100
   ```

3. Verify Xray is listening on port 12345:
   ```bash
   sudo ss -tlnp | grep 12345
   ```

### Connection Issues

1. Check Xray logs for errors (authentication, TLS, etc.)
2. Verify server domain is accessible: `ping <your-domain>`
3. Test direct connection without TProxy (use SOCKS5 proxy)
4. Check firewall rules aren't blocking outbound connections

### DNS Issues

1. Verify DNS queries are being intercepted:
   ```bash
   sudo nft list table inet xray_tproxy -a | grep "dport 53"
   ```

2. Test DNS directly:
   ```bash
   dig @1.1.1.1 google.com
   ```

### Permission Errors

1. Verify capabilities are set:
   ```bash
   getcap /opt/Xray-linux-64/xray
   ```

2. Verify xray user exists:
   ```bash
   id xray
   ```
