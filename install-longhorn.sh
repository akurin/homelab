#!/bin/bash
set -euo pipefail

# Deliberately no --rollback-on-failure here, unlike the other install scripts. It implies
# --wait, and on this cluster's single small node Longhorn's first bring-up (disk
# registration, CSI sidecar leader election) can exceed the timeout even when it would have
# converged fine. On a *first* install there's no previous release to roll back to, so Helm
# falls back to uninstalling what it just deployed — which then trips Longhorn's
# deleting-confirmation-flag guard and leaves the release wedged in `uninstalling` with the
# resources still running. That has already happened once; see k3s.md.
#
# --take-ownership adopts resources that exist without a matching Helm release, which is
# exactly the state that wedged install leaves behind. It makes this script self-healing at
# the cost of silently claiming resources owned by another release — acceptable here, where
# nothing else manages longhorn-system.
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install --take-ownership \
	longhorn longhorn/longhorn \
	--namespace longhorn-system \
	--create-namespace \
	--version 1.12.0 \
	--set defaultSettings.defaultReplicaCount=1 \
	--set persistence.defaultClassReplicaCount=1 \
	--set csi.attacherReplicaCount=1 \
	--set csi.provisionerReplicaCount=1 \
	--set csi.resizerReplicaCount=1 \
	--set csi.snapshotterReplicaCount=1 \
	--set longhornUI.replicas=1 \
	--set persistence.defaultClass=false
