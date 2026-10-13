---
paths:
  - "validate/**"
---
# validate.py conventions

- Python 3, standard library plus `psycopg[binary]` only. `argparse`, `logging`, no secrets printed.
- Runs on the bastion. Reaches Postgres through `kubectl port-forward svc/airis-core-rw <local>:5432` started as a subprocess, never through a NodePort or LoadBalancer.
- Every check is a small function returning `{"name", "passed", "evidence"}`. Checks, in order: Kubernetes API reachable on the private IP; node Ready; CNPG operator deployment available; Cluster phase `Cluster in healthy state` with `readyInstances == instances` and a `currentPrimary`; write/read round trip on a scratch table (cleaned up); replication (`pg_stat_replication` count ≥ instances-1); TLS on the connection (`pg_stat_ssl`); negative tests (node has no ExternalIP, direct TCP to `<k3s-ip>:5432` refused, no Service of type LoadBalancer or NodePort); optional `--chaos` (delete the primary pod, time until a new primary is healthy).
- Password comes from the Kubernetes secret `airis-core-app` via `kubectl get secret -o jsonpath`, held in memory only.
- Output: a console table plus `handover_report.json` with timestamp and per-check results. Exit code 1 if any check fails.
- Keep it under ~200 lines; it must be retypable from memory in 25 minutes.
