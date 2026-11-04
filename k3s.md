# K3s Cluster

## Architecture

Three nodes: two cloud VPS (`k3s-server` control plane, `k3s-agent` worker) and **x13**, the home
laptop, reserved for explicitly selected workloads.

- **Node identity** comes from the overlay: `flannel-iface: wg-k3s` is set on every node and no
  `node-ip` is pinned, so K3s uses the overlay address (`10.44.0.1`, `10.44.0.2`, `10.44.0.3`).
  Kubelet is therefore reachable from the control plane over the overlay.
- **Overlay**: `wg-k3s`, UDP 51822, MTU **1380**, carrying **AmneziaWG** — a WireGuard fork whose
  junk packets, padded handshakes and custom header types stop the censored home link from
  fingerprinting the tunnel. x13 connects directly; the cloud peers have no configured endpoint for
  it and learn it by roaming.
- **Flannel** runs over the overlay with the **host-gw** backend (`flannel-iface: wg-k3s`,
  `flannel-external-ip: false`): no encapsulation, pod MTU **1380**, and each node routes its peers'
  pod /24s through `wg-k3s`. WireGuard's `AllowedIPs` therefore include each peer's pod subnet
  (`k3s_node_pod_cidr` in `host_vars/`), which must match Flannel's real lease — check with
  `kubectl get nodes -o custom-columns=NAME:.metadata.name,PODCIDR:.spec.podCIDR` after a rebuild or
  when adding a node, then re-run `ansible/k3s.yml --tags amneziawg`.
- **API access** is `https://10.44.0.1:6443` on every node, and the API advertises that overlay
  address, so agents never learn a public endpoint a NAT'd peer could not reach. Nothing is allowed
  to use the server's public 6443: if the overlay is down, recovery is SSH to the server.
- **Overlay module**: `amneziawg-dkms` builds it. Ubuntu kernels from 7.0.13 carry an API change the
  packaged 1.0.0 source mishandles; `ansible/roles/amneziawg/files/amneziawg-compat-7.0.13.patch` fixes it.
  The `amneziawg` role installs headers for the **boot kernel** and rebuilds it, so a reboot after a
  kernel upgrade is safe; `dkms status` shows what is built.

This shape is forced by the network: plain WireGuard from the home link is dropped and the laptop has
no routable address. It avoids an intermediary: ~55–110 ms direct, versus 175–290 ms when relayed through
the proxy. Flannel, node identity and the API all ride the overlay, so no other part of the
cluster knows which transport carries it.

## Nodes

| Node | Address | Role | Workload policy |
|---|---|---|---|
| k3s-server | 193.181.212.97 | Control plane | tainted `NoSchedule` |
| k3s-agent | 193.181.216.56 | Cloud worker | runs cluster workloads |
| x13 | 192.168.1.100 (LAN) | Home worker | only explicitly selected workloads |

DNS points to the server IP. x13 runs nothing by default: `homelab.morjoff.com/workload=home` **and**
a `dedicated=home:NoSchedule` toleration are both required. Taints are scheduling policy, not an
authorization boundary — broad-toleration DaemonSets can still land there. If x13 is offline, a pinned
workload stays `Pending` rather than moving to the cloud worker.

## Networking

Each node runs **nftables** as the only firewall, with two kinds of rule:

- **Trusted wholesale:** the pod, service and overlay CIDRs (`10.42.0.0/16`, `10.43.0.0/16`,
  `10.44.0.0/24`). The overlay is WireGuard-authenticated, which covers Flannel's port, kubelet and
  the API without per-peer rules.
- **Open to any source:** SSH (22) on every node; HTTP/HTTPS (80/443) on the cloud worker for
  ServiceLB/Traefik ingress; UDP 51822 on the cloud nodes, because x13's home NAT source is not
  guaranteed stable.

Everything else is dropped — no public port for the API (6443), kubelet (10250) or Flannel (51820).
Default: drop incoming, accept forward (CNI rules live in the forward chain). There is no cloud
firewall in front of the nodes; IPv4/IPv6 forwarding is enabled by both K3s roles.

## Ingress

**Traefik** is the default IngressClass and runs on the cloud worker: its HelmChartConfig requires a
node without the control-plane role, and x13's taint keeps it off the laptop. Traffic still enters on
the server's public IP, where ServiceLB forwards it:

```
Internet → server public IP → ServiceLB → Traefik (cloud worker) → service ClusterIP → pod
```

TLS certificates come from **cert-manager** with the `letsencrypt-prod` ClusterIssuer.

## Storage

**Longhorn** provides block storage, scheduled only on the cloud worker (x13's storage belongs to the
laptop), so `defaultReplicaCount` and the CSI sidecar counts are `1`. Replicas cannot span nodes here,
so there is no in-cluster redundancy: back volumes up externally. It costs roughly **200 MiB at
rest** plus **85–100 MiB per volume**, which caps it well under ten volumes on this node — far below
Longhorn's documented 4 vCPU / 4 GiB minimum, so it is an experiment rather than a recommendation.
`open-iscsi` is required on any node it schedules to (the `open_iscsi` role).

**`local-path` is the default StorageClass; `longhorn` deliberately is not.** `local-path` comes from
a K3s-packaged manifest whose annotation is re-applied on upgrade, so Longhorn yields (via
`persistence.defaultClass=false` in `install-longhorn.sh`). Anything that wants Longhorn must name
`storageClassName: longhorn`; a PVC that names nothing gets `local-path`.

**Longhorn's admission webhook is cluster-wide.** `longhorn-webhook-validator` validates
`persistentvolumeclaims` UPDATE with empty selectors and `failurePolicy: Fail`, so while Longhorn is
unhealthy **no PVC in any namespace can be updated** — including `local-path` ones and Helm releases
that own a PVC. Provisioning and mounting on `local-path` still work; `helm upgrade` on a chart with a
PVC does not.

The UI has no ingress; port-forward it through the server:

```
ssh -L 8080:127.0.0.1:8080 root@193.181.212.97 \
	'kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml -n longhorn-system port-forward svc/longhorn-frontend 8080:80'
```

## Capacity and failure modes

The cloud worker has **1 vCPU / 1.7 GiB** and runs the cluster workloads. This is the constraint
behind every other tuning choice here.

- **Swap:** 2 GiB on both cloud nodes, managed by the `swap` role as a `swapfile.swap` systemd unit
  (`swap_enabled: true` in the host vars). kubelet's `memorySwap` is unset, i.e. `NoSwap` — **containers
  get no swap**; only host processes (k3s, containerd, Alloy) benefit. Swap provides headroom, not
  capacity; the durable fixes are fewer pods or a larger instance.
- **One core means CPU storms look like memory failures.** A workload that is heavy at startup (an
  image that runs `composer install` on every restart, for example) pins the core and produces probe
  timeouts, kills and restart loops that look like a capacity problem in a snapshot. Sample over
  minutes before concluding a workload does not fit, and keep startup work off this node.
- **Alloy is best-effort on the control plane:** `SCHED_IDLE` (`CPUWeight=idle` plus
  `CPUSchedulingPolicy=idle`) and a hard `MemoryMax=400M` with **no `MemoryHigh`**. It cannot starve
  the API — under a 60 % competing load it used ~2–5 % of the core and the API stayed at ~120 ms p95
  with no timeouts. It still costs ~200 MiB and ~30 % of an idle core, because the Fleet-managed
  node-exporter and journald pipelines run there; trimming that integration is the first lever if
  headroom becomes tight. The Fleet pipelines read `GCLOUD_RW_API_KEY` from the unit environment, so a
  hand-run `alloy run` without it reports `401 invalid token` that the service never logs.
- **`k3s-agent` can take minutes to report active** while the API is slow; the node is `Ready` before
  systemd considers the unit started, so `systemctl restart k3s-agent` can appear hung. The unit is
  left as upstream ships it.

## CI deploys

CI reaches the API through a restricted SSH tunnel from the `ci_deploy_key` role: a `ci-deploy` user
whose only authorized key is forwarding-restricted (`permitopen="127.0.0.1:6443"`, no shell/pty/agent
forwarding). Consumers run `ssh -L 6443:127.0.0.1:6443 -N ci-deploy@<server>` and point
`kubectl`/`helm` at `127.0.0.1:6443`.

The local forward must be **port 6443** — the `KUBECONFIG` secret holds K3s's self-generated
kubeconfig, which points at `https://127.0.0.1:6443`, so any other local port fails with "connection
refused" even though the tunnel is up. In GitHub Actions, open the tunnel and run the command that
uses it in the **same step**; a backgrounded `ssh -N` from one step is not reliably alive in the next.

## Key configuration

- Node addresses live in `ansible/inventory/host_vars/`; `ansible/inventory/group_vars/k3s_cluster.yml` holds the overlay
  settings, including `amneziawg_params` — every peer must use identical values.
- Overlay lifecycle: the first play of `ansible/k3s.yml` runs the `amneziawg` role over all of
  `k3s_cluster` (`--tags amneziawg` runs only that play). It installs the tooling and the
  boot-kernel module, generates a private key on each host the first time, exchanges the public
  halves in the play, and renders the peers. Nothing has to be prepared in inventory, but every
  member must take part in the run: a `--limit` that selects only some hosts skips the play and
  keeps the existing mesh. K3s takes `flannel-iface`, `advertise-address` and the API endpoint
  from its own config templates.
- K3s version is pinned in `ansible/roles/k3s_server/defaults/` and `ansible/roles/k3s_agent/defaults/`. Pod and
  service CIDRs are defined there and in `ansible/k3s.yml`, and referenced by the nftables trusted
  sources.
- All K3s runtime flags (token, node-external-ip, flannel backend, CIDRs, tls-san, …) live in
  `ansible/roles/k3s_server/templates/config.yaml.j2` and `ansible/roles/k3s_agent/templates/config.yaml.j2`, rendered
  to `/etc/rancher/k3s/config.yaml` and reapplied (with a restart) on every Ansible run — the single
  source of truth for install flags, not the one-shot install command.
- Traefik config (IngressClass, nodeAffinity, tolerations) lives in
  `ansible/roles/k3s_server/templates/traefik-config.yaml.j2`, applied as a K3s HelmChartConfig.
