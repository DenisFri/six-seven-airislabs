#!/bin/bash
# Runs ON the bastion. Creates the Airis Core Postgres cluster and waits until CNPG calls it healthy.
set -euo pipefail
NS="airis-core"
NAME="airis-core"

kubectl apply -f "$(dirname "$0")/airis-core.yaml"

# First run: image pull through NAT + initdb + replica join, usually 2-4 minutes.
for _ in $(seq 1 90); do
  phase="$(kubectl -n "$NS" get cluster "$NAME" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  ready="$(kubectl -n "$NS" get cluster "$NAME" -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)"
  echo "$(date +%T)  phase='${phase:-<none yet>}'  ready=${ready:-0}"
  if [[ "$phase" == "Cluster in healthy state" && "$ready" == "2" ]]; then
    kubectl cnpg status "$NAME" -n "$NS"
    kubectl -n "$NS" get pods,svc,pvc
    exit 0
  fi
  sleep 5
done

echo "not healthy after 7.5 min. Debug: kubectl -n $NS get pods; kubectl -n $NS describe cluster $NAME" >&2
exit 1
