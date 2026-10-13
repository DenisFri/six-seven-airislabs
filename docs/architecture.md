# Architecture, decisions, traps

Short reference for the on-site. `/quiz` uses "Decisions and trade-offs"; `/chaos` uses "Known traps".

## Target design

```
Office / laptop (admin_cidr)
      │ tcp/22 only
      ▼
┌─ six-seven-vpc ── subnet 10.10.0.0/24 (me-west1) ──────────────────────────┐
│  six-seven-bastion  e2-small, public IP, tag bastion                        │
│      │ tcp/22 + tcp/6443, source tag bastion only                           │
│      ▼                                                                      │
│  six-seven-k3s  e2-standard-2, NO public IP, tag k3s                        │
│      K3s (single server)                                                    │
│        ├─ cnpg-system: CNPG operator (Helm)                                 │
│        └─ airis-core:  Cluster airis-core, 2 instances (primary + replica)  │
│                        services: airis-core-rw / -ro / -r (ClusterIP only)  │
│  Cloud Router + Cloud NAT (toggle enable_nat) → outbound-only internet      │
└─────────────────────────────────────────────────────────────────────────────┘
validate.py runs on the bastion: kubectl port-forward svc/airis-core-rw → checks → handover_report.json
```

## Firewall table

| Rule | Direction | From | To | Ports |
|------|-----------|------|----|-------|
| six-seven-allow-admin-ssh-bastion | ingress | `admin_cidr` (/32) | tag `bastion` | tcp 22 |
| six-seven-allow-bastion-to-k3s | ingress | tag `bastion` | tag `k3s` | tcp 22, 6443 |
| (implied) | ingress | anything else | anything | denied |
| (implied) | egress | VMs | internet via NAT (k3s) or public IP (bastion) | allowed |

## Decisions and trade-offs (the skeptical-client list)

1. **Own VPC, not the default network.** Default has auto-subnets everywhere and open SSH/RDP/ICMP rules; policies often delete it. Zero Trust starts from nothing.
2. **Bastion with a public IP, restricted to one /32.** Stricter: IAP TCP forwarding (no public IP at all, ingress from 35.235.240.0/20) plus OS Login with 2FA. Planned as a Terraform toggle after the basics work.
3. **Tags for firewall targets.** Stricter: rules by service account, because tags can be edited by anyone with instance-admin rights.
4. **Metadata SSH keys with `block-project-ssh-keys`.** Stricter: OS Login (IAM-managed users, 2FA, audit). Fallback if an org policy forces it.
5. **Cloud NAT for egress.** "Accessible only via the bastion" is about inbound; NAT is outbound only. Built as a toggle: on for bootstrap, off for zero egress. Stricter: proxy on the bastion; no internet with Private Google Access + Artifact Registry mirrors; air-gapped.
6. **Dedicated service accounts with no roles.** The default compute SA carries Editor; a compromised VM could rebuild the project.
7. **Shielded VM on.** Free, often required by policy.
8. **Single K3s node.** Time-boxed exercise. HA needs 3 server nodes (embedded etcd) and node anti-affinity for Postgres.
9. **CNPG, not Bitnami/Zalando/Patroni.** CNCF project, native streaming replication, declarative failover, Kubernetes-native backups.
10. **`instances: 2`.** One primary, one streaming replica: enough to demo failover without exhausting an 8 GB node. `preferred` anti-affinity becomes real when nodes are added.
11. **`local-path` storage.** Fine for phase 1; node-bound. HA path: a CSI-backed class (GCE PD CSI driver or Longhorn).
12. **Port-forward for validation.** Postgres stays ClusterIP-only; nothing is exposed. Production path: internal load balancer or private connectivity plus mTLS, never a NodePort.
13. **Local Terraform state.** Fine for 90 minutes. Production: GCS backend with state locking, one state per environment.
14. **Debian 12 image family.** Small, standard on GCP, patched automatically on rebuild. Pin an exact image for strict reproducibility.
15. **`e2-standard-2` for K3s.** `e2-medium` (4 GB) is tight for k3s + operator + two Postgres instances; OOMKilled costs more time than the cents saved.

### Sizing method (one-minute answer)

- RAM: working set should fit `shared_buffers` (~25% RAM) + OS cache (`effective_cache_size` ~75%). `work_mem × max_connections × sorts per query` must fit too; use a pooler (CNPG `Pooler`/PgBouncer) to cap connections.
- Disk: rows × row size × (1 + index factor ~0.5–1.0) × bloat headroom 1.3 × growth horizon, plus WAL retention; keep 20–30% free.
- IOPS: write TPS drives WAL writes; on GCP IOPS scale with disk type and size (pd-balanced vs pd-ssd), so pick the disk for IOPS, not only capacity.
- CPU: concurrent active queries, not total connections. Validate with `pgbench`.

## Known traps (for `/chaos`)

| Symptom | Cause | Proof command |
|---------|-------|---------------|
| k3s install hangs; pods `ImagePullBackOff` | no Cloud NAT, or NAT in another region | `curl -m 5 https://get.k3s.io` from the k3s VM |
| `terraform plan`: could not find default credentials | missing `gcloud auth application-default login` | `gcloud auth application-default print-access-token` |
| apply: API has not been used in project | Compute API off | `gcloud services list --enabled` |
| ssh: connection timed out | firewall: admin IP changed, tag missing | `curl.exe ifconfig.me` vs `admin_cidr`; `gcloud compute instances describe … --format="get(tags.items)"` |
| ssh: Permission denied (publickey) | wrong user, wrong `-i` key, OS Login forced | `ssh -v`, check metadata `ssh-keys`, `enable-oslogin` |
| kubectl on bastion: connection refused / permission denied | kubeconfig root-only or still points at 127.0.0.1 | `cat ~/.kube/config | grep server` |
| Postgres pod `Pending` | PVC not bound: wrong storage class name | `kubectl get pvc -n airis-core`, `kubectl get storageclass` |
| Postgres pod `OOMKilled` / CrashLoop | memory limit too low, `e2-medium` | `kubectl describe pod`, `logs --previous` |
| apply: `ZONE_RESOURCE_POOL_EXHAUSTED` | zone out of capacity | switch `zone` letter, apply |
| apply fails: resource already exists | created outside Terraform or state lost | `terraform import`, `terraform state list` |
| bash script: `\r: command not found` | CRLF line endings | `file script.sh` |

## Demo flow (last 5 minutes)

1. `terraform output` — two IPs, no console opened.
2. `ssh six-seven-k3s` through the bastion; `kubectl get nodes`, `kubectl get cluster -n airis-core`.
3. `python3 validate.py --report handover_report.json` — all PASS; show the negative tests.
4. Optional: `--chaos` failover timing; `enable_nat = false` apply → cluster still healthy, VM has no internet.
5. `terraform destroy` plan to show clean teardown (run only if they want it).
