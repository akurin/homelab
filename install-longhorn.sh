#!/bin/bash
set -euo pipefail

helm repo add longhorn https://charts.longhorn.io
helm repo update
helm upgrade --install --rollback-on-failure \
	longhorn longhorn/longhorn \
	--namespace longhorn-system \
	--create-namespace \
	--version 1.12.0 \
	--set defaultSettings.defaultReplicaCount=1 \
	--set persistence.defaultClassReplicaCount=1 \
	--set csi.attacherReplicaCount=1 \
	--set csi.provisionerReplicaCount=1 \
	--set csi.resizerReplicaCount=1 \
	--set csi.snapshotterReplicaCount=1
