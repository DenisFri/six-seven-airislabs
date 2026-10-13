---
paths:
  - "terraform/**"
---
# Terraform conventions

- One file per concern: `versions.tf providers.tf variables.tf network.tf firewall.tf nat.tf bastion.tf k3s.tf outputs.tf`.
- Every variable has `description` and `type`. No hardcoded project id, region, zone, or IPs in resources.
- Names: `six-seven-<thing>`, lowercase and hyphens. Comments explain why, not what.
- Cycle Denis runs: `terraform fmt` → `validate` → `plan` (state the expected "N to add/change/destroy" before he runs it) → `apply` → verify with a gcloud list/describe → `git commit`.
- Pin the provider to `"~> X.0"` using the major version in `.terraform.lock.hcl` after the first `init`.
- Firewall model: ingress denied by default, egress allowed. Sources: `admin_cidr` (IP range) for the bastion, `source_tags` for internal traffic. Tags tie rules to VMs.
- No public IP = no `access_config` block. Public IP = empty `access_config {}` (ephemeral) or `nat_ip` from `google_compute_address` (static).
- Keep `enable_nat` as a `count` toggle. Router, NAT and subnet share `var.region`.
- Every VM: dedicated service account with no roles, minimal scopes, `shielded_instance_config`, `block-project-ssh-keys = "true"`.
- Outputs for both IPs (`bastion_public_ip`, `bastion_private_ip`, `k3s_private_ip`). Scripts read them with `terraform output -raw`.
- Secrets: `*.tfvars` and `*.tfstate*` are gitignored. No `terraform.tfvars.example`: `variables.tf` with its descriptions is the reference.
- Common errors to name immediately: "could not find default credentials" (ADC login), "API has not been used" (Compute API), `ZONE_RESOURCE_POOL_EXHAUSTED` (switch zone letter), "connection timed out" (firewall) vs "Permission denied (publickey)" (user or key).
