# Six Seven — Airis Core phase 1 on GCP

Terraform (VPC, bastion, private K3s VM, Cloud NAT) → K3s → CloudNativePG Postgres → Python validation from the bastion.

- Brief: `docs/assignment.md`
- Design, trade-offs, traps: `docs/architecture.md`
- Step-by-step log: `docs/build-log.md` · status: `docs/plan.md`
- Code: `terraform/` · `k3s/` · `validate/`

## On site (fresh laptop, fresh project)

1. Clone: `git clone https://github.com/DenisFri/six-seven-airislabs.git` (fallback: the zip on the USB stick).
2. Tools. Windows: `winget install Google.CloudSDK Hashicorp.Terraform` (ssh ships with Windows). macOS: `brew install google-cloud-sdk terraform`.
3. Bring it up, phase by phase (prereqs → gcloud → key → tfvars → terraform → sshconfig → tools → k3s → cnpg → postgres → validate):
   ```powershell
   .\scripts\up.ps1 -ProjectId <project-id>
   ```
   Two browser logins, one key passphrase, one "Apply? y" after the plan. About 15 minutes of waiting in total.
   If PowerShell refuses scripts: `powershell -ExecutionPolicy Bypass -File scripts\up.ps1 -ProjectId <project-id>`.
   A phase failed → `docs/failure-playbook.md` → `.\scripts\up.ps1 -From <phase>`.
4. Demo: `docs/demo.md`, minutes 85–90. Report: `validate/handover_report.json`.
5. Tear down and prove the project is empty: `.\scripts\down.ps1`.

No Windows on the provided machine? Every phase is a block of plain commands in `docs/demo.md`; type them.
