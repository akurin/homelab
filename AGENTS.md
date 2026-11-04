# Repository context for agents

Ansible-managed homelab: a K3s cluster of two cloud VPS nodes plus the home laptop **x13**, and an
Xray deployment that provides connectivity from a censored home network.

For K3s or x13 work, read [k3s.md](k3s.md) first: it describes the current architecture, why it is
shaped that way, and the known limitations. `ansible/inventory/` is the source of truth: `k3s.yml` lists membership only,
`host_vars/` holds per-node configuration and `group_vars/` the cluster-wide settings.

Cluster changes go through the playbooks; `ansible/k3s.yml` is the complete deployment entry point
(it builds the overlay, then the control plane and agents). Run only the overlay role with
`--tags amneziawg`. Do not store investigation logs in the repository: record durable architecture
and motivation in `k3s.md` instead.
