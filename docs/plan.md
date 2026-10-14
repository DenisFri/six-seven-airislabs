# Plan and status

Step numbers match `docs/build-log.md`. `/step` reads this file; `/log` updates it.
Status: `done` · `in progress` · `next` · `todo`

| Step | What | Status | Proof |
|------|------|--------|-------|
| 0 | Workbench: gcloud, Terraform, SSH client, Windows notes | done | versions print |
| 0a | GCP project `airislabs-six-seven`, billing, 20 USD alert budget | done | console |
| 1 | Connect gcloud: login, ADC login, set project, enable Compute + IAM APIs | done | `gcloud config list` |
| 2 | SSH key `~/.ssh/airis` + repo folders + `git init` | done | `ls $HOME\.ssh` |
| 3 | Terraform skeleton: versions, provider, variables, VPC + subnet | done | applied |
| 4 | Firewall: admin → bastion (22), bastion → k3s (22, 6443) | done | applied |
| 5 | Cloud Router + Cloud NAT as `enable_nat` toggle | done | applied, index 0 |
| 6 | Bastion VM + outputs + first SSH login | done | `whoami` = fde (2026-10-13); `block-project-ssh-keys` apply + pins commit carried into 7 |
| 7 | K3s VM (no public IP) + `k3s_private_ip` output + SSH config with ProxyJump | done | `ssh six-seven-k3s` → hostname + NAT IP `34.165.222.20` (2026-10-13) |
| 8 | Bastion tooling via startup script: kubectl, helm, python3, pip, psycopg, cnpg plugin | done | `kubectl get nodes` runs from the bastion (2026-10-14) |
| 9 | K3s install over `ssh -J` + kubeconfig on the bastion | done | `six-seven-k3s Ready control-plane v1.36.5+k3s1` from the bastion (2026-10-14) |
| 10 | Helm + CNPG operator in `cnpg-system` | done | committed `c385da2` (2026-10-14); pod-Running line not pasted |
| 11 | Postgres `Cluster` `airis-core`, 2 instances | done | healthy 2/2, primary airis-core-1 (2026-10-14, `49f483e`) |
| 12 | `validate.py` + `requirements.txt` + JSON report | done | 11/11 PASS incl. chaos failover 15 s (2026-10-14 07:37 UTC) |
| 13 | Demo flow, failure playbook, NAT-off demo, `terraform destroy` | in progress | docs written; rehearsal + clean destroy pending |
| 14 | On-site scripts `scripts/up.ps1` (11 phases, `-From`) + `scripts/down.ps1` (destroy + proof + ssh cleanup) | in progress | written, parsed on PS 5.1; end-to-end run against a destroyed project pending |

## After the build

- Timed drills from a blank folder: `/drill terraform` 20 min · `/drill k3s` 10 · `/drill cnpg` 15 · `/drill python` 25 · `/drill full` 90
- Chaos drills: `/chaos`, one trap per run, diagnosed without the repo
- Skeptical-client rehearsal: `/quiz`
- 5-minute architecture presentation: three slides (diagram + firewall table · data layer + HA path + sizing method · validation + trade-offs)
- Send the three questions to the POC (see `docs/build-log.md`, "Before the on-site")

## Open items

- Bastion `kubectl` (upstream stable) vs k3s API `v1.36`: check the skew once with `kubectl version` on the bastion
- Interview date: not set yet. Once known, lay out the day-by-day schedule.
