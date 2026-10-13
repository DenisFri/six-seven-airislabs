#!/bin/bash
# Bastion tooling. Runs as root on every boot, so every step must be safe to repeat.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Right after boot, unattended-upgrades may hold the apt lock: wait instead of failing.
apt-get -q -o DPkg::Lock::Timeout=120 update
apt-get -q -o DPkg::Lock::Timeout=120 install -y python3 python3-venv

# kubectl: upstream stable. Allowed skew to the k3s API server is one minor.
KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod 0755 /usr/local/bin/kubectl

# helm: official installer
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# cnpg kubectl plugin: cluster status, promote, reload
curl -fsSL https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | sh -s -- -b /usr/local/bin

# Debian 12 refuses system-wide pip installs (PEP 668), so validate.py gets its own venv.
python3 -m venv /opt/venv
/opt/venv/bin/pip install -q "psycopg[binary]"
