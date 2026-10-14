#!/bin/bash
# Runs ON the bastion. Installs the CloudNativePG operator with Helm.
set -euo pipefail
CHART_VERSION="0.29.1"

helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg

# upgrade --install: one command for the first install and every later upgrade.
# --wait: return only when the operator deployment is ready.
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --version "${CHART_VERSION}" \
  --values "$(dirname "$0")/cnpg-values.yaml" \
  --wait --timeout 5m

kubectl -n cnpg-system get pods
kubectl get crd clusters.postgresql.cnpg.io
