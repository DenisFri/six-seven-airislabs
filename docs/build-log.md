# Six Seven Project — Build Log

**Company:** Airis Labs — Forward Deployed Engineer, on-site assignment (90 min)
**Goal:** Day 0 = Terraform (VPC, bastion, private K3s VM) + CNPG Postgres on K3s. Day 1 = Python validation script run from the bastion.
**Repo:** `C:\repos\six-seven-airislabs`
**Laptop:** Windows, PowerShell, gcloud CLI + Terraform installed
**Started:** 2026-10-12

## Repo layout

| Folder | What goes there |
|---|---|
| `terraform/` | Network, firewall, NAT, bastion VM, K3s VM |
| `k3s/` | K3s install script, CNPG Helm values, Postgres `Cluster` manifest |
| `validate/` | `validate.py` + `requirements.txt` (runs on the bastion) |
| `docs/` | This log, architecture, trade-offs, failure playbook |

## Target architecture (short)

- Own VPC, one subnet.
- Bastion VM: small, public IP, SSH allowed only from the office IP.
- K3s VM: no public IP. SSH (22) and Kubernetes API (6443) allowed only from the bastion.
- Cloud NAT: lets the private VM download k3s and pull container images.
- K3s single node → CNPG operator (Helm) → Postgres cluster (primary + 1 replica).
- Python script on the bastion checks everything and writes a JSON report.

Rule: **gcloud** for the few "before" tasks (login, pick project, enable APIs). **Terraform** for everything inside the project.

---

## Step 0 — Workbench

https://developer.hashicorp.com/terraform/install



- [x] gcloud CLI installed
- [x] Terraform installed
- [x] `ssh -V` works in PowerShell (SSH client is built into Windows)

Windows notes:
- PowerShell on the laptop; bash only runs on the VMs. Terraform is the same on both.
- SSH config lives in `C:\Users\<you>\.ssh\config`. The "jump through the bastion" rule goes there later.
- **Line endings:** save every `.sh` file with LF, not CRLF. In VS Code click "CRLF" bottom-right → "LF". A CRLF script fails on Linux with `\r: command not found`.

## Step 0a — Create the GCP project (console)

- [x] Project created: **AirisLabs Six Seven**
- [x] Project ID: `airislabs-six-seven` (commands use the ID, not the name)
- [x] Billing linked
- [x] Budget `airislabs-six-seven-alert`: all services, 20 USD, alerts 50/90/100 %. (Spend caps only cover Cloud Run / Functions / Vertex / Gemini, not Compute Engine, so alert-only.)

Why manual: a project is the box Terraform works inside. Terraform can't create the box it lives in. On site, the client gives you this box ready.

Budget alerts only email you; they never stop spending. `terraform destroy` at the end of every session is your job.

## Step 1 — Connect gcloud to the project

```powershell
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
gcloud services enable compute.googleapis.com iam.googleapis.com
gcloud config list
```

| Command | What it does | If you skip it |
|---|---|---|
| `auth login` | logs the gcloud command in as you (opens browser) | nothing works |
| `config set project` | picks the project and remembers it | wrong or no project |
| `auth application-default login` | second login; writes the separate credentials file that **Terraform** reads | Terraform: "could not find default credentials" |
| `services enable ...` | turns on the Compute + IAM APIs (off in new projects), takes ~1 min | Terraform: "API has not been used in project ..." |
| `config list` | shows account + project so you can confirm | — |

- [x] Done

## Step 2 — SSH key + repo folder

```powershell
mkdir $HOME\.ssh -Force
ssh-keygen -t ed25519 -f $HOME\.ssh\airis -C airis-fde
```

- ed25519 = modern, short key type.
- One key only for this job → easy to revoke after handover.
- No passphrase for practice; use one on site.
- [x] Key created: `C:\Users\<you>\.ssh\airis` (private) + `airis.pub` (public)

```powershell
cd C:\repos
mkdir six-seven-airislabs\terraform, six-seven-airislabs\k3s, six-seven-airislabs\validate, six-seven-airislabs\docs
cd six-seven-airislabs
git init
```

- [x] Folders created (docs, k3s, terraform, validate)
- [x] `git init` done

## Step 3 — Terraform skeleton: VPC + subnet

Goal: an empty, custom network. Small win first; firewall, NAT and VMs stack on top.

Why our own VPC and not the default network: the default comes with auto-made subnets in every region and loose firewall rules (SSH, RDP, ICMP open to the internet). Zero Trust = start from nothing, open only what is needed. Many companies also delete the default network by policy, so it may not exist on site.

Files in `terraform\`:

`versions.tf` — pins Terraform + provider so the code behaves the same on site:
```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"   # after init: tighten to "~> X.0" using the major in .terraform.lock.hcl
    }
  }
}
```

`providers.tf` — where the Google plugin works:
```hcl
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
```

`variables.tf` — all knobs in one place, nothing hardcoded:
```hcl
variable "project_id" {
  description = "GCP project ID (the ID, not the name)"
  type        = string
}

variable "region" {
  description = "Region for subnet, NAT and VMs"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone for the VMs"
  type        = string
  default     = "europe-west1-b"
}

variable "subnet_cidr" {
  description = "IP range of our single subnet"
  type        = string
  default     = "10.10.0.0/24"
}
```

`network.tf` — the infrastructure:
```hcl
resource "google_compute_network" "vpc" {
  name                    = "six-seven-vpc"
  auto_create_subnetworks = false # custom mode: we define the one subnet ourselves
}

resource "google_compute_subnetwork" "private" {
  name                     = "six-seven-subnet"
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true # VMs with no public IP can still reach Google APIs
}
```

`terraform.tfvars` — real values, never committed:
```hcl
project_id = "airislabs-six-seven"
```

`.gitignore` (repo root): `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfvars`, `kubeconfig*`, `__pycache__/`

Commands (in `terraform\`):
```powershell
terraform init       # downloads the Google plugin → .terraform\ and .terraform.lock.hcl (exact version)
terraform fmt        # formats
terraform validate   # syntax + references, no cloud calls
terraform plan       # shows changes: expect "2 to add"
terraform apply      # creates them after "yes" → writes terraform.tfstate (Terraform's memory; never delete, never commit)
```

| What breaks | Cause |
|---|---|
| "could not find default credentials" | missing `gcloud auth application-default login` |
| "API has not been used in project" | Compute API not enabled |
| 403 / 404 | wrong project ID |

Verify: `gcloud compute networks subnets list --network=six-seven-vpc`
Commit: `git add . ; git commit -m "terraform: vpc and subnet"`

- [x] `terraform plan` → 2 to add
- [x] `terraform apply` done, subnet visible in gcloud
- [x] provider version pinned `~> 8.0` (2026-10-13). Lock file stays gitignored; the `~>` pin is the guard.
- [x] committed

## Step 4 — Firewall rules

Goal: open exactly two doors. In a VPC, incoming traffic is blocked by default and outgoing is allowed, so we only write "allow in" rules. Rules attach to VMs through tags, so they can exist before the VMs do.

| Rule | From | To | Ports | Why this source |
|---|---|---|---|---|
| admin → bastion | my public IP `/32` (on site: the office IP) | tag `bastion` | tcp 22 | the one door from the internet: name exactly who may knock |
| bastion → k3s | tag `bastion` | tag `k3s` | tcp 22, 6443 | identity, not IP: the bastion's IP doesn't exist yet, and tags survive rebuilds |

Find my public IP: `curl.exe ifconfig.me` (the `.exe` matters in PowerShell).

`variables.tf` add:
```hcl
variable "admin_cidr" {
  description = "Public IP (/32) allowed to SSH to the bastion. On site: the office egress IP."
  type        = string
}
```
`terraform.tfvars` add: `admin_cidr = "x.x.x.x/32"`

`firewall.tf`:
```hcl
# Ingress is denied by default; each rule opens exactly one door.

resource "google_compute_firewall" "admin_to_bastion" {
  name      = "six-seven-allow-admin-ssh-bastion"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.admin_cidr]
  target_tags   = ["bastion"]
}

resource "google_compute_firewall" "bastion_to_k3s" {
  name      = "six-seven-allow-bastion-to-k3s"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"] # ssh + Kubernetes API for kubectl on the bastion
  }

  source_tags = ["bastion"]
  target_tags = ["k3s"]
}
```

Commands: `terraform fmt`, `plan` (2 to add, or 4 if Step 3 was not applied yet), `apply`, `git commit -m "terraform: firewall rules"`
Verify: `gcloud compute firewall-rules list --filter="network:six-seven-vpc"`

| What breaks | Cause |
|---|---|
| invalid `source_ranges` | bare IP without `/32` |
| type error on ports | ports must be strings: `["22"]` |
| name rejected | uppercase or underscore in the name |

**Region decision (2026-10-12):** final choice `me-west1` (Tel Aviv), zone `me-west1-a`. For our two VMs the price difference between regions is cents, so what matters is: machine types exist there, and latency (Tel Aviv ≈ 10 ms, Iowa ≈ 150 ms from Israel). Region and zone are variables, so a change is one line. If apply fails with `ZONE_RESOURCE_POOL_EXHAUSTED`, switch the zone letter. Check types before committing to a zone: `gcloud compute machine-types list --filter="zone:ZONE AND (name=e2-small OR name=e2-standard-2)"`

- [x] `terraform plan` → rules correct
- [x] applied
- [x] committed

## Step 5 — Cloud Router + Cloud NAT (as a toggle)

Goal: outbound-only internet for the private VM (k3s download, image pulls). NAT rewrites outgoing traffic with a Google-owned public IP and lets the replies back in. Nothing can start a connection inward: the VM has no public IP and NAT only works outward. "Accessible only via the bastion" is about inbound; NAT is outbound. No conflict.

Why they most likely expect NAT: 30 minutes for Terraform + K3s, and NAT is the standard GCP answer in three resources. The differentiator is defending it and knowing the stricter options:
1. NAT as a switch: on for bootstrap, off afterwards. Images are cached on the node, so steady state needs no internet. **Built** (`enable_nat`).
2. Egress through a proxy on the bastion: one controlled, logged exit. More moving parts.
3. No internet at all: Private Google Access + Artifact Registry mirrors for ghcr.io / Docker Hub, k3s binaries staged in a bucket. Enterprise-grade, lots more Terraform.
4. Air-gapped: hand-carry tarballs through the bastion. Slow, error-prone.

`variables.tf` add:
```hcl
variable "enable_nat" {
  description = "Outbound internet for the private subnet. true during bootstrap, false afterwards for zero egress."
  type        = bool
  default     = true
}
```

`nat.tf`:
```hcl
# The K3s VM has no public IP. Cloud NAT gives it outbound-only internet
# (k3s download, container image pulls). Nothing can start a connection inward.

resource "google_compute_router" "router" {
  count   = var.enable_nat ? 1 : 0 # count = 0 means "don't create this"
  name    = "six-seven-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  count                              = var.enable_nat ? 1 : 0
  name                               = "six-seven-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"                     # Google picks the public IP
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" # we have one subnet

  log_config {
    enable = true
    filter = "ERRORS_ONLY" # evidence for the client if egress ever fails
  }
}
```

Say on site: NAT only serves VMs without a public IP (the bastion ignores it). NAT, router and subnet must share a region. Switch off: `enable_nat = false` in tfvars + apply removes both; Postgres keeps running, the K3s VM can no longer reach the internet (demo-able).

Verify: `gcloud compute routers nats list --router=six-seven-router --region=me-west1`

| What breaks | Cause |
|---|---|
| nothing fails now; 20 min later the k3s install hangs and pods sit in `ImagePullBackOff` | NAT missing, or in a different region than the subnet. The #1 trap in this setup. |

- [x] applied (router + nat, index 0)
- [x] committed

## Step 6 — Bastion VM

How SSH login works on GCP: `ssh user@ip` → the VM checks that `user` exists and that your public key is in that user's `~/.ssh/authorized_keys`. On a normal server you create the user and paste the key yourself. On GCP a small agent on the VM does it: it reads the instance metadata field `ssh-keys` (lines of `username:public-key`), creates that Linux user with sudo, and places the key. So the username is just the word before the colon, our choice. We use `fde` on both VMs. Alternative: OS Login (users managed by IAM, username derived from the Google account), the fallback if an org policy forces it.

`variables.tf` add:
```hcl
variable "ssh_user" {
  description = "Linux user created on both VMs for SSH"
  type        = string
  default     = "fde"
}

variable "ssh_public_key_path" {
  description = "Public key allowed to log in (the private half never leaves the laptop)"
  type        = string
  default     = "~/.ssh/airis.pub"
}
```

`bastion.tf`:
```hcl
# Dedicated service account with no project roles: the bastion needs an identity,
# not GCP powers. (The default compute SA carries Editor, which is far too much.)
resource "google_service_account" "bastion" {
  account_id   = "six-seven-bastion"
  display_name = "Bastion VM"
}

resource "google_compute_instance" "bastion" {
  name         = "six-seven-bastion"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["bastion"] # ties the firewall rules to this VM

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {} # empty block = give me a public IP (ephemeral)
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
    block-project-ssh-keys = "true" # ignore keys added at project level by others
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"]
  }
}
```

**Block by block (study notes):**
1. `resource "google_compute_instance" "bastion"` — type + local name. The local name is how other code refers to it; it is not the VM name.
2. `name` — VM name in GCP; unique in the project, lowercase + hyphens.
3. `machine_type = "e2-small"` — 2 shared vCPUs (~half a core), 2 GB. Enough for ssh/kubectl/helm/python. `e2-micro` too tight, `e2-medium` not needed.
4. `zone = var.zone` — VMs are zonal; zone must be inside the subnet's region.
5. `tags = ["bastion"]` — labels the firewall looks at; rules with `target_tags`/`source_tags` apply only to VMs carrying the tag. No tag = no SSH. Stronger alternative: rules by service account (tags can be edited by anyone with instance-admin rights).
6. `boot_disk { initialize_params }` — OS disk from image family `debian-cloud/debian-12` (family = newest Debian 12 image). Size in GB; type defaults to `pd-balanced`.
7. `network_interface` — `subnetwork` = plugged into our subnet (private IP from 10.10.0.0/24). `access_config {}` = also a public IP; empty = ephemeral (changes on stop/start); `nat_ip` + `google_compute_address` = static. **No `access_config` block = no public IP** (that is the K3s VM).
8. `metadata` — key/value store the VM reads from inside (`metadata.google.internal`). Guest agent turns `ssh-keys` (`user:key`) into Linux users + authorized_keys. Expression inside-out: `pathexpand(~)` → `file()` → `trimspace()` → `"fde:ssh-ed25519 ..."`. `block-project-ssh-keys = "true"` ignores project-level keys. Alternative: OS Login (IAM users, 2FA, audit) — fallback if org policy demands it.
9. `shielded_instance_config` — secure boot (signed boot code only), vTPM (records boot measurements), integrity monitoring (logs if boot differs from baseline). Free; often required by policy.
10. `service_account` — the VM's identity towards Google APIs. Omit the block = default compute SA with **Editor** role (a compromised bastion could rebuild the project). Ours: dedicated SA, no roles. Scopes = older second limit on what the VM token may ask for (logs + metrics only). Role AND scope must both allow.

**Why `outputs.tf`:** Terraform knows the public IP only after apply (it lives in the state). An output is a named, stable way to read it: `terraform output bastion_public_ip` (`-raw` for scripts). Outputs = the public interface of your Terraform code. Alternatives: console (not scriptable), `gcloud compute instances describe ... --format="get(networkInterfaces[0].accessConfigs[0].natIP)"` (re-asks Google, hard to type), `terraform state show` (dumps everything), reading tfstate by hand (don't).

`outputs.tf`:
```hcl
output "bastion_public_ip" {
  description = "SSH entry point"
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

output "bastion_private_ip" {
  value = google_compute_instance.bastion.network_interface[0].network_ip
}
```

Commands:
```powershell
terraform fmt; terraform plan   # 2 to add: service account + VM
terraform apply
$ip = terraform output -raw bastion_public_ip
ssh -i $HOME\.ssh\airis fde@$ip
```
Inside: `whoami` (fde), `hostname`, `curl -s ifconfig.me` (prints the VM's public IP), `exit`.

| What breaks | Cause |
|---|---|
| connection timed out | firewall: your public IP changed → fix `admin_cidr`, apply |
| Permission denied (publickey) | wrong user (word before the colon), wrong `-i` key, or OS Login forced by org policy so metadata keys are ignored |
| key file error on Windows | icacls fix from Step 2 |
| "no file exists" at plan | `ssh_public_key_path` wrong; check `ls $HOME\.ssh` |

**Static vs ephemeral IP (tried 2026-10-13, decided: ephemeral).** `nat_ip = google_compute_address.bastion.address` keeps the IP across stop/start and VM replacement, so the SSH config and the office allowlist never change. Same cost while attached; `terraform destroy` releases it anyway. Say on site: "ephemeral is enough for the exercise; a long-lived bastion gets a reserved address, one more resource." Two traps when trying it: the address must be declared (`Reference to undeclared resource`), and `network_tier` must match on the address and the `access_config` (default PREMIUM; STANDARD only saves egress money, pointless for a bastion).

**Version pins (2026-10-13):** `required_version = "~> 1.16"`, provider `version = "~> 8.0"`. `~>` = "only the last number may grow": two numbers (`~> 8.0`) = 8.x, three numbers (`~> 1.0.0`) = 1.0.x only. The lock file stays gitignored; the `~>` pin is what stops a surprise provider 9.0 on site.

**Decisions:** no `terraform.tfvars.example` (`variables.tf` with its descriptions is the reference). `.gitignore` also ignores `.venv/`, `*.pem`, `*.key`. The key has a passphrase (ProxyJump asks twice per login → `ssh-agent`, Step 7).

| What breaks | Cause |
|---|---|
| `Unsupported Terraform Core version` | `~> 1.0.0` allows only 1.0.x. Use `~> 1.16`. |
| `Reference to undeclared resource` | `nat_ip` points at a `google_compute_address` that was never written |
| network tier mismatch at apply | address PREMIUM (default) vs `access_config` STANDARD |

Commit: `git commit -m "terraform: bastion vm"` → done as `added bastion vm`

- [x] applied, SSH works, `whoami` = fde (2026-10-13)
- [x] committed (`added bastion vm`)
- [ ] `block-project-ssh-keys` applied: plan shows `0 to add, 1 to change` → carried into Step 7's apply
- [ ] version pins + `.gitignore` committed → carried into Step 7's commit

Bastion and NAT were left running overnight 2026-10-12 → 13 (no destroy). End every session with `/teardown`.

## Before the on-site — questions to send the POC

1. Workstation and connectivity: own laptop or a provided machine? Is outbound internet (GitHub, Helm/CNPG chart repos, pip) open from the office? Is bringing pre-prepared code fine?
2. Project constraints: IAM role, enabled APIs, region, and org policies to design around (external IP restriction, OS Login requirement, Shielded VM).
3. Sizing: is there an expected load profile for Airis Core phase 1, or should I present a sizing methodology with stated assumptions?

## Think about (questions I should be able to answer on site)

- Why our own VPC instead of the default network? → see Step 3.
- Firewall sources: IP range for admin → bastion, tag for bastion → k3s. → see Step 4.
- NAT: outbound-only way out; inbound stays zero. → see Step 5.
- SSH login on GCP: metadata `ssh-keys` = `username:key`; the agent creates the user. → see Step 6.
- `~>` version constraints: two numbers = minor may grow, three = patch only. → see Step 6.
- Static vs ephemeral bastion IP, in one sentence. → see Step 6.
- The K3s VM has no public IP. How do you SSH to it from the laptop in one command, without copying the private key to the bastion?

## Next

Step 7 — Terraform: K3s VM (no public IP) + SSH ProxyJump config.
