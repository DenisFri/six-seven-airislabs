#!/bin/bash
# Runs ON the k3s VM (copied there with scp). Single server, embedded SQLite.
# Needs Cloud NAT: this VM has no public IP and get.k3s.io is on the internet.
set -euo pipefail

# The bastion talks to the API at this address, so the API certificate must carry it.
# (k3s adds the node IP by itself; explicit means no surprise if the node ever has two.)
NODE_IP="$(hostname -I | awk '{print $1}')"

# --write-kubeconfig-mode 644  : fde can read the kubeconfig, needed for the copy to the bastion
# --disable traefik, servicelb : no ingress, no LoadBalancer. Nothing listens on the node
#                                except SSH and the API (6443). Postgres stays ClusterIP-only.
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --tls-san "${NODE_IP}" \
  --disable traefik \
  --disable servicelb

# The installer returns when the service starts, not when the API answers.
until kubectl get nodes >/dev/null 2>&1; do sleep 2; done
kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes -o wide
