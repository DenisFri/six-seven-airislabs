# Six Seven — FDE on-site practice (Airis Labs)

Denis is preparing for a 90-minute on-site assignment: Terraform (VPC, bastion, private K3s VM),
CNPG Postgres on K3s, and a Python validation script, on a fresh GCP project.
This repo is both the practice build and the prepared solution.
Claude is the coach. Denis types the code and runs every command that changes the cloud.

## Read first

- @docs/plan.md — step order and current status ("where are we")
- `.claude/rules/` loads automatically: coaching rhythm, docs sync, per-folder conventions
- `docs/assignment.md` the brief · `docs/architecture.md` design, trade-offs, traps · `docs/build-log.md` the full log
- `docs/demo.md` the 90-minute run sheet · `docs/failure-playbook.md` symptom → layer → proof → fix

## Fixed facts (decided, don't reopen unless Denis asks)

- GCP project `airislabs-six-seven`, region `me-west1`, zone `me-west1-b`, subnet `10.10.0.0/24`
- VPC `six-seven-vpc`, subnet `six-seven-subnet`
- Bastion `six-seven-bastion`: e2-small, public IP, tag `bastion`, Debian 12, Shielded VM, own service account with no roles
- K3s VM `six-seven-k3s`: e2-standard-2, **no public IP**, tag `k3s`
- Firewall: tcp/22 to `bastion` only from `admin_cidr`; tcp/22 + tcp/6443 to `k3s` only from source tag `bastion`
- Cloud NAT is a toggle: `enable_nat` (on for bootstrap, off for zero egress)
- SSH user `fde`, key `~/.ssh/airis`; private key never leaves the laptop; `block-project-ssh-keys = true`
- Postgres: CNPG operator (Helm, ns `cnpg-system`), cluster `airis-core` in ns `airis-core`, 2 instances, `local-path` storage
- `validate.py` runs on the bastion through `kubectl port-forward`; Postgres stays ClusterIP-only

## Environment

- Laptop: Windows. Denis runs commands in **PowerShell** (`$HOME\.ssh\airis`, `curl.exe`, `Copy-Item`).
- Claude's own Bash tool on Windows is **Git Bash**: use `/c/repos/...` paths and bash syntax there.
- Repo: `C:\repos\six-seven-airislabs` → `terraform/` `k3s/` `validate/` `docs/`
- Obsidian mirror of `docs/build-log.md`:
  `C:\Users\denis\Documents\Obsidian\JobSearch\Airis Labs\Six Seven Project.md`
  Start Claude with `--add-dir` on that folder so `/log` can write it.

## Commands Denis runs

- Terraform cycle, in `terraform\`: `terraform fmt; terraform validate; terraform plan` → `terraform apply` → verify with gcloud → `git commit`
- SSH: `$ip = terraform output -raw bastion_public_ip; ssh -i $HOME\.ssh\airis fde@$ip`
- Slash commands: `/step` next step · `/log` docs + Obsidian · `/drill <area>` timed rebuild · `/chaos` break-and-fix · `/quiz` skeptical client · `/teardown` end of session

## Hard rules

- Never run `terraform apply/destroy`, `kubectl apply/delete`, `helm install/uninstall`, or any gcloud write command. Show the command; Denis runs it and pastes the result. `.claude/settings.json` enforces the deny list.
- Never read, print, or paste into docs: `terraform.tfstate`, kubeconfig, private keys, passwords. Public IPs are fine.
- `.sh` files: LF line endings. Gitignored: `*.tfvars` (no `.example` file: `variables.tf` with its descriptions is the reference), `*.tfstate*`, `kubeconfig*`, `drills/`, `CLAUDE.local.md`.
- Every session ends with `/teardown` so nothing keeps costing money.
