#!/bin/bash
set -euo pipefail

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable-cloud-controller" sh -
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/k3s.yml
