# K3s Cluster

## Nodes

Two nodes managed by `ansible/k3s.yml`:

| Node       | Public IP       | Role          |
|------------|-----------------|---------------|
| k3s-server | 193.181.212.97  | Control plane |
| k3s-agent  | 193.181.216.56  | Worker        |

DNS points to the server IP. The server is tainted (`node-role.kubernetes.io/control-plane:NoSchedule`) so workloads
only run on the agent.

## Networking

Nodes communicate over k3s's built-in multicloud networking: `--node-external-ip` (each node's public IP) plus
`--flannel-backend=wireguard-native` + `--flannel-external-ip`, so cluster-internal pod traffic is wrapped in a
flannel-managed WireGuard tunnel between the two public IPs — no separate VPN (Tailscale/Headscale) is involved.
Flannel generates and exchanges the WireGuard keys itself; there's no manual key setup.

Each node runs **nftables** for host-level firewall:

- Public: SSH (22), HTTP (80), HTTPS (443), SMTP (25 — agent only)
- Trusted, unscoped: pod CIDR (`10.42.0.0/16`), service CIDR (`10.43.0.0/16`)
- Trusted, port-scoped (`nftables_trusted_source_rules` in `ansible/k3s.yml`): the peer node is only trusted for
  flannel's WireGuard tunnel (UDP 51820) plus whatever it actually needs from the other side — the API server
  (TCP 6443) on the server, kubelet (TCP 10250, for `kubectl logs`/`exec`) on the agent
- Default: drop incoming, accept forward (K3s CNI rules live in the forward chain)

nftables is the sole firewall — there is no cloud firewall in front of these nodes.

`net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` are enabled by both `k3s_server` and `k3s_agent` roles
(required for flannel to route pod traffic across the WireGuard tunnel).

## Ingress

**Traefik** is the default IngressClass (`isDefaultClass: true`), pinned to the server node via nodeAffinity +
toleration. Traffic flow:

```
Internet → server public IP → Traefik → service ClusterIP → pod (on agent)
```

TLS certificates are issued by **cert-manager** using the `letsencrypt-prod` ClusterIssuer.

## Storage

**Longhorn** provides block storage via `install-longhorn.sh`. Since the agent is the only schedulable node (see
Nodes above), `defaultReplicaCount` and the CSI sidecar replica counts are set to `1` — replicas can't span nodes
when there's only one to schedule onto, so Longhorn's usual multi-node redundancy doesn't apply here; back up
volumes externally rather than relying on in-cluster replication for durability.

`install-vultr-csi.sh` and the `vultr-csi/` chart also live in this repo but are **not installed** on this cluster
(the nodes are Vultr instances and Vultr still provides DNS, SSH keys and firewall groups, but no Vultr Block
Storage volumes are attached).

**`local-path` is the default StorageClass; `longhorn` is deliberately not.** Both charts ship wanting to be
default, and when both were annotated `is-default-class: true` Kubernetes broke the tie by newest
`creationTimestamp` — which `longhorn` happened to win, but only by accident of install order.

k3s is the wrong side of that to fight: `local-path` comes from a packaged manifest
(`/var/lib/rancher/k3s/server/manifests/local-storage.yaml`) applied through k3s's addon controller, so the
annotation is re-applied whenever that manifest's checksum changes, e.g. on a k3s upgrade. Longhorn's StorageClass
is ours, so it yields instead: `persistence.defaultClass=false` in `install-longhorn.sh`.

Consequence: **anything that wants Longhorn must name it explicitly** (`storageClassName: longhorn`); a PVC that
doesn't name a class gets `local-path`. That's intentional — it keeps the Longhorn experiment opt-in and leaves a
working storage path if Longhorn degrades under the constraints described below.

Longhorn on this node costs roughly **200 MiB at rest**, plus **~85-100 MiB per volume** (measured: 197 MiB idle,
298 MiB with a single 1 GiB volume provisioned but unattached). With ~1.2 GiB available that's a practical ceiling
of well under ten volumes. Running it here at all is a deliberate experiment in how Longhorn behaves under
constraint, not a recommendation — it is far below the documented 4 vCPU / 4 GiB per-node minimum.

Prerequisite: `open-iscsi` (`iscsid`) must be installed and running on any node Longhorn schedules to — handled by
the `open_iscsi` role, wired into the `k3s_agent` play in `ansible/k3s.yml`.

### Reaching the Longhorn UI

There's no public ingress for it. Port-forward through SSH in one hop, running `kubectl port-forward` on the server
itself (root has a working kubeconfig at `/etc/rancher/k3s/k3s.yaml` there):

```
ssh -L 8080:127.0.0.1:8080 root@193.181.212.97 \
	'kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml -n longhorn-system port-forward svc/longhorn-frontend 8080:80'
```

Then open `http://127.0.0.1:8080`. Leave the SSH session running while using the UI.

## Memory and swap

`k3s-agent` has **1 vCPU and 1.7 GiB** and runs the entire workload, since the server is tainted `NoSchedule`. That
is well under what this stack wants (Longhorn alone documents a 4 vCPU / 4 GiB per-node minimum), and the failure
mode it produces is worth recognising because it doesn't look like a memory problem at first.

**Symptom:** Traefik crash-loops — liveness probe `GET /ping` times out, kubelet kills the container (exit 137), it
restarts, repeat. Because Traefik is the only ingress path, every domain on the cluster intermittently hangs mid-TLS
handshake. Longhorn's CSI sidecars fail the same way (`context deadline exceeded` connecting to their own unix
socket).

**Actual cause:** memory, not CPU. With swap off, anonymous memory (the Go heaps of k3s, containerd, Alloy, Traefik,
Longhorn's ~11 pods, cert-manager's 3) is unreclaimable, so `kswapd0` can only reclaim page cache — and the working
set doesn't fit. Pages get evicted and immediately faulted back in, continuously. Measured at its worst:

| | thrashing | with 2 GiB swap |
|---|---|---|
| CPU idle | 0% | 77% |
| CPU sys time | 84% | 8% |
| load average (1 min) | 5.4 | 1.0 |
| page-cache refaults | 23,700/sec | 4,200/sec |
| PSI memory `full` (avg60) | 12.9% | 3.4% |

The CPU saturation was a *symptom* — 84% of it was kernel time spent on reclaim and fault handling. This is why
lowering Alloy's scheduling priority (`CPUWeight`/`Nice`, in the `grafana_alloy` role) did not help: scheduling
weights redistribute CPU, they don't shrink anyone's memory footprint, and reclaim happens in kernel threads that
don't answer to a service's cgroup weight. Swap fixed it by giving cold anonymous pages somewhere to go — Alloy's
resident set alone dropped from 97 MiB to 18 MiB.

Useful signals when diagnosing this, all on the node itself:

```
cat /proc/pressure/memory          # 'full' above a few percent means real stalling
grep -E 'workingset_refault_file|pgscan_kswapd|pgmajfault' /proc/vmstat   # sample twice, diff
top -bn1                           # high 'sy' + low 'id' + kswapd0 near the top
```

Swap is enabled on the agent only, by the `swap` role (`swap_enabled: true` in `ansible/k3s.yml`); the server keeps
the conventional Kubernetes swap-off setup, which is the role's default. k3s's kubelet already runs with
`failSwapOn: false`, so no kubelet change was needed. Note that kubelet's `memorySwap` behaviour is unset, i.e.
`NoSwap` — **containers get no swap at all**; only host-level processes (Alloy, k3s, containerd) benefit. Even
setting `swapBehavior: LimitedSwap` would only cover Burstable pods, and almost every pod here is BestEffort
because no resource requests are set.

Swap is a mitigation, not a fix. The node is still oversubscribed, and the durable options are fewer pods on it
(Longhorn is ~11 pods for storage nothing currently uses) or a larger instance.

## CI deploys

CI pipelines reach the API server through a restricted SSH tunnel set up by the `ci_deploy_key` role: a `ci-deploy`
user on the server whose only authorized key is forwarding-restricted (`permitopen="127.0.0.1:6443"`, no
shell/pty/agent-forwarding) to `127.0.0.1:6443`. A consumer opens
`ssh -L 6443:127.0.0.1:6443 -N ci-deploy@<server>` and points `kubectl`/`helm` at `127.0.0.1:6443`.

The local forward must be **port 6443, not some other local port** — the `KUBECONFIG` secret holds k3s's
self-generated kubeconfig as-is, which always points at `server: https://127.0.0.1:6443` (k3s's standard default),
so the tunnel has to land on that exact local port or the client gets "connection refused" even though the tunnel
itself came up fine.

In GitHub Actions specifically, set up the tunnel and run the command that uses it (`helm`/`kubectl`) **within the
same step** — each step is a separate process invocation, and a backgrounded `ssh -N` from one step isn't reliably
still alive by the time a later step tries to use it.

## Key configuration

- K3s version is pinned in `ansible/roles/k3s_server/defaults/main.yml` and `ansible/roles/k3s_agent/defaults/main.yml`
- Pod CIDR and service CIDR are defined in `k3s_server/defaults/main.yml` and `ansible/k3s.yml`'s play vars, and
  referenced by both the k3s config and the nftables trusted sources
- All k3s runtime flags (token, node-external-ip, flannel backend, cidrs, tls-san, ...) live in
  `ansible/roles/k3s_server/templates/config.yaml.j2` / `k3s_agent/templates/config.yaml.j2`, rendered to
  `/etc/rancher/k3s/config.yaml` and reapplied (with a restart) on every Ansible run — this is the single source of
  truth for install flags, not the one-shot install command
- Traefik config (IngressClass, nodeAffinity, tolerations) lives in
  `ansible/roles/k3s_server/templates/traefik-config.yaml.j2`, applied as a K3s HelmChartConfig
