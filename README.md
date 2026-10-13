# Six Seven — Airis Core phase 1 on GCP

Terraform (VPC, bastion, private K3s VM, Cloud NAT) → K3s → CloudNativePG Postgres → Python validation from the bastion.

- Brief: `docs/assignment.md`
- Design, trade-offs, traps: `docs/architecture.md`
- Step-by-step log: `docs/build-log.md` · status: `docs/plan.md`
- Code: `terraform/` · `k3s/` · `validate/`

Quick start (laptop, PowerShell): `gcloud auth login`, `gcloud auth application-default login`, copy `terraform/terraform.tfvars.example` to `terraform.tfvars`, then `terraform init && terraform apply` in `terraform/`.
