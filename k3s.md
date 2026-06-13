# K3s Cluster

## Nodes

Two nodes managed by `ansible/k3s.yml`:

| Node              | Public IP       | Role          | Provider               |
|-------------------|-----------------|---------------|------------------------|
| prod-k3s-server-0 | 193.181.212.97  | Control plane | —                      |
| prod-k3s-agent-0  | 209.250.225.251 | Worker        | Vultr (migrating away) |

DNS points to the server IP. The server is tainted (`node-role.kubernetes.io/control-plane:NoSchedule`) so workloads
only run on the agent.

## Networking

Nodes communicate over **Tailscale** (`tailscale0`). K3s is configured with `--flannel-iface tailscale0` and
`--node-ip <tailscale_ip>`, so all cluster-internal traffic (API server, kubelet, etcd, flannel) stays on the Tailscale
overlay.

Each node runs **nftables** for host-level firewall:

- Public: SSH (22), HTTP (80), HTTPS (443), SMTP (25 — server only), Tailscale (UDP 41641)
- Trusted: `tailscale0` interface, pod CIDR (`10.42.0.0/16`), service CIDR (`10.43.0.0/16`)
- Default: drop incoming, accept forward (K3s CNI rules live in the forward chain)

nftables is the sole firewall — there is no cloud firewall in front of these nodes.

## Ingress

**Traefik** is the default IngressClass (`isDefaultClass: true`), pinned to the server node via nodeAffinity +
toleration. Traffic flow:

```
Internet → server public IP → Traefik → service ClusterIP → pod (on agent)
```

TLS certificates are issued by **cert-manager** using the `letsencrypt-prod` ClusterIssuer.

## Key configuration

- K3s version is pinned in `ansible/roles/k3s_server/defaults/main.yml` and `ansible/roles/k3s_agent/defaults/main.yml`
- Pod CIDR and service CIDR are defined in `k3s_server/defaults/main.yml` and referenced in both the k3s install flags
  and the nftables trusted sources
- Traefik config (IngressClass, nodeAffinity, tolerations) lives in
  `ansible/roles/k3s_server/templates/traefik-config.yaml.j2`, applied as a K3s HelmChartConfig
