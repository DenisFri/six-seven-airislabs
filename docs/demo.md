# On-site run sheet (90 minutes)

Clock targets from the brief. Typed from memory; the repo is the fallback, not the plan.

## Before the clock (laptop check, 5 min before start)

```powershell
gcloud --version; terraform version; ssh -V; python --version
ssh-keygen -t ed25519 -f $HOME\.ssh\airis -C airis-fde      # passphrase on site
Start-Service ssh-agent; ssh-add $HOME\.ssh\airis
curl.exe ifconfig.me                                          # the office IP → mngmt_cidr
```

## 0–5 min: architecture (three slides, `docs/architecture.md`)

1. Diagram + firewall table. The sentence: "one door in (bastion, one /32), one path out (NAT), everything else denied by default."
2. Data layer: CNPG, 2 instances, automatic failover, HA path (worker → node-to-node rule → zones → etcd → CSI), sizing method.
3. Validation: what the script proves, including what must *not* work, and the trade-off list.

## 5–35 min: Terraform + K3s

```powershell
gcloud auth login; gcloud config set project PROJECT_ID; gcloud auth application-default login
gcloud services enable compute.googleapis.com iam.googleapis.com
```

Files, in this order: `versions.tf` `providers.tf` `variables.tf` `network.tf` `firewall.tf` `nat.tf` `bastion.tf` + `bastion-startup.sh` `k3s.tf` `outputs.tf`, `terraform.tfvars` (project_id, mngmt_cidr, enable_nat = true).

```powershell
terraform init; terraform fmt; terraform validate; terraform plan   # 10 to add
terraform apply
terraform output
```

Expected 10 resources: vpc, subnet, 2 firewall rules, router, nat, 2 service accounts, 2 VMs.

SSH config (`$HOME\.ssh\config`): `six-seven-bastion` (public IP) and `six-seven-k3s` (private IP, `ProxyJump six-seven-bastion`).

```powershell
ssh six-seven-bastion "sudo google_metadata_script_runner startup"     # tools, ~2 min, can run in a second window
scp .\k3s\install-k3s.sh six-seven-k3s:~/; ssh six-seven-k3s "bash ~/install-k3s.sh"
.\k3s\copy-kubeconfig.ps1                                             # ends with: six-seven-k3s Ready
```

Say while waiting: why own VPC, why tags, why NAT is outbound-only, why the kubeconfig needs the sed.

## 35–65 min: CNPG + Postgres

```powershell
scp .\k3s\cnpg-values.yaml .\k3s\install-cnpg.sh .\k3s\airis-core.yaml .\k3s\deploy-airis-core.sh six-seven-bastion:~/
ssh six-seven-bastion "bash ~/install-cnpg.sh"          # operator Running, CRD present
ssh six-seven-bastion "bash ~/deploy-airis-core.sh"     # ends with kubectl cnpg status: healthy, 2/2
```

Say while waiting: why an operator (failover, replication, rolling updates are code, not runbooks), why `instances: 2`, requests/limits, `preferred` anti-affinity, `local-path` and the CSI path, how the DB size is calculated (`architecture.md`, sizing method).

## 65–85 min: Python

```powershell
.\validate\run-validate.ps1             # all PASS, exit 0, handover_report.json back on the laptop
.\validate\run-validate.ps1 --chaos     # plus failover timing
```

Walk through: `check()` turns every exception into a FAIL line · port-forward is the only path · credentials from the Secret, never printed · negative tests · exit code for CI.

## 85–90 min: demo

1. `terraform output`: two IPs. No console was opened.
2. `ssh six-seven-k3s hostname` through the bastion; `kubectl get nodes`; `kubectl get cluster -n airis-core`.
3. The report: open `handover_report.json`, point at the three negative checks and the failover seconds.
4. If time: `enable_nat = false` → `terraform apply` (2 to destroy) → `kubectl get cluster` still healthy, `ssh six-seven-k3s "curl -m 5 ifconfig.me"` hangs. Zero egress, database unaffected.
5. Teardown offer: `terraform plan -destroy` shows 10 to destroy; run `terraform destroy` only if they want the project clean.

## Teardown (every practice session, and on site if asked)

```powershell
cd terraform; terraform destroy          # type yes; ~2 min
gcloud compute instances list            # must be empty
gcloud compute routers list              # must be empty
```

Cost of forgetting: two VMs + NAT ≈ 3 USD/day.

## If behind schedule

- 35 min, k3s not up: skip the tooling explanation, keep typing; explain while the install runs.
- 65 min, Postgres not healthy: show the manifest and explain it, then run the script anyway. A FAIL line that is correct is a result.
- 85 min, script not done: run the checks by hand (`kubectl cnpg status`, `kubectl cnpg psql … -c "select pg_is_in_recovery()"`, `kubectl get svc -A`), describe the report format.
