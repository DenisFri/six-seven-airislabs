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

## Step 7 — K3s VM (no public IP) + SSH ProxyJump

Goal: the private VM, reachable only through the bastion, and one SSH command from the laptop that gets there without the private key ever leaving the laptop.

Why `e2-standard-2` (2 vCPU, 8 GB): k3s ~1 GB + CNPG operator + two Postgres instances with explicit memory requests. `e2-medium` (4 GB) ends in OOMKilled. Disk 20 GB: k3s binaries, images and Postgres data (`local-path`) all live on it.

`k3s.tf` — same pattern as the bastion, two differences: no `access_config`, bigger machine:
```hcl
# Same pattern as the bastion host, but for the k3s cluster. (No public IP)
# Bigger machine type: k3s + CNPG operator + two Postgres pods (>= 4 GB)
resource "google_service_account" "k3s" {
  account_id   = "six-seven-k3s"
  display_name = "K3s VM"
}

resource "google_compute_instance" "k3s" {
  name         = "six-seven-k3s"
  machine_type = "e2-standard-2"
  zone         = var.zone
  tags         = ["k3s"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config: no public IP. In only through the bastion. Out only through NAT.
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
    block-project-ssh-keys = "true"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.k3s.email
    scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"]
  }
}
```

`outputs.tf` add:
```hcl
output "k3s_private_ip" {
  description = "K3s node; reachable only through the bastion"
  value       = google_compute_instance.k3s.network_interface[0].network_ip
}
```

Commands: `terraform fmt; terraform validate; terraform plan` → **2 to add, 1 to change** (SA + VM, plus the Step 6 metadata change) → `apply` → `terraform output -raw k3s_private_ip` → `10.10.0.3`.

`C:\Users\denis\.ssh\config`:
```
Host six-seven-bastion
  HostName 34.165.78.24
  User fde
  IdentityFile ~/.ssh/airis
  IdentitiesOnly yes

Host six-seven-k3s
  HostName 10.10.0.3
  User fde
  IdentityFile ~/.ssh/airis
  IdentitiesOnly yes
  ProxyJump six-seven-bastion
```

How ProxyJump works: ssh connects to the bastion, asks it to open a plain TCP tunnel to `10.10.0.3:22`, then runs the *second* SSH handshake through that tunnel, from the laptop. The bastion forwards encrypted bytes and never sees the key. Alternatives: agent forwarding (`-A`) lets a compromised bastion use your key while you are connected; copying the private key to the bastion: never.

Passphrase + ProxyJump = two prompts per login. Fix: Windows ssh-agent (service is Disabled by default; admin PowerShell, once): `Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent; ssh-add $HOME\.ssh\airis`

Verify: `ssh six-seven-k3s "hostname; curl -s -m 5 ifconfig.me"` → `six-seven-k3s` + NAT IP `34.165.222.20` (≠ bastion `34.165.78.24`). One line proves both claims: in only via the bastion, out only via NAT.

| What breaks | Cause |
|---|---|
| hop 2: connection timed out | VM missing tag `k3s`, or the bastion→k3s rule without `source_tags` |
| hop 2: Permission denied (publickey) | `ssh` run without the config, so no key offered on the second hop |
| `curl` hangs | NAT off, or in another region than the subnet |
| config ignored | saved as `config.txt`, or `Host` typo |
| `ZONE_RESOURCE_POOL_EXHAUSTED` | no `e2-standard-2` free in the zone; switch the zone letter |

**"Suitable for future HA expansion?" (asked 2026-10-13):** HA lives in CNPG today (2 instances, automatic failover, *preferred* anti-affinity). The platform is one node, one zone, on purpose. Path, no teardown: add a worker (`K3S_URL` + token; the replica moves there by itself) → `k3s → k3s` firewall rule (6443, 2379-2380, 10250 tcp, 8472 udp; today nodes never talk to each other) → zones as a list variable (the subnet is regional) → control plane: SQLite → embedded etcd in place with `--cluster-init`, then 3 servers → optional CSI driver for node-independent disks. What would have blocked it: Postgres straight on the VM, NodePort/hostPath tied to one node, the default network.

Commit: `git add terraform/ ; git commit -m "terraform: k3s vm, ssh proxyjump"`

- [x] plan → 2 to add, 1 to change; applied (`plan` now: No changes)
- [x] `ssh six-seven-k3s` → `six-seven-k3s`, `34.165.222.20` (2026-10-13)
- [x] Step 6 leftovers committed (`9812fc8`)
- [ ] `k3s.tf` + `outputs.tf` committed
- [ ] `bastion_private_ip` description

## Step 8 — Bastion tooling via startup script

Goal: the bastion installs its own tools at boot (kubectl, helm, cnpg plugin, Python venv with psycopg). On site: zero manual typing; a rebuilt bastion comes back identical.

`.gitattributes` (repo root) first. Git here has `core.autocrlf = true`, so every text file gets CRLF on checkout, and a `.sh` with CRLF dies on Linux with `\r: command not found`. One line forces LF for scripts, whatever the global setting:
```
*.sh text eol=lf
```
Check: `git check-attr eol -- terraform/bastion-startup.sh` → `eol: lf`. VS Code status bar must also say `LF` when saving.

`terraform/bastion-startup.sh`:
```bash
#!/bin/bash
# Bastion tooling. Runs as root on every boot, so every step must be safe to repeat.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Right after boot, unattended-upgrades may hold the apt lock: wait instead of failing.
apt-get -q -o DPkg::Lock::Timeout=120 update
apt-get -q -o DPkg::Lock::Timeout=120 install -y python3 python3-venv

# kubectl: upstream stable. Allowed skew to the k3s API server is one minor.
KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod 0755 /usr/local/bin/kubectl

# helm: official installer
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# cnpg kubectl plugin: cluster status, promote, reload
curl -fsSL https://github.com/cloudnative-pg/cloudnative-pg/raw/main/hack/install-cnpg-plugin.sh | sh -s -- -b /usr/local/bin

# Debian 12 refuses system-wide pip installs (PEP 668), so validate.py gets its own venv.
python3 -m venv /opt/venv
/opt/venv/bin/pip install -q "psycopg[binary]"
```

`bastion.tf`, one line in `metadata`:
```hcl
    startup-script = file("${path.module}/bastion-startup.sh")
```
Why the `metadata` key and not the `metadata_startup_script` argument: the argument **replaces** the VM on every script change (new ephemeral IP, SSH config edit). The key updates in place; the script runs at the next boot, or by hand: `sudo google_metadata_script_runner startup`. That command is also the on-site debug tool; its log: `sudo journalctl -u google-startup-scripts -n 30`.

Commands: `terraform fmt; terraform validate; terraform plan` → **0 to add, 1 to change** → `apply` → `ssh six-seven-bastion "sudo google_metadata_script_runner startup"` (1–2 min) → verify:
`ssh six-seven-bastion "kubectl version --client; helm version --short; kubectl cnpg version; /opt/venv/bin/python -c 'import psycopg; print(psycopg.__version__)'"`

| What breaks | Cause |
|---|---|
| `\r: command not found` | CRLF: `.gitattributes` missing, or VS Code saved CRLF |
| `externally-managed-environment` | pip outside a venv on Debian 12; that is why `/opt/venv` |
| nothing installed after apply | metadata key runs at boot only: run the script runner, or reboot |
| script stops halfway | `set -e`: the first failed download aborts; read journalctl |
| apt lock held right after boot | `unattended-upgrades`; `-o DPkg::Lock::Timeout=120` waits instead of failing |
| kubectl skew warning later | bastion kubectl more than one minor from the k3s API; pin `KUBECTL_VERSION` |
| on site: GitHub/PyPI blocked | POC question 1; fallback `apt-get install python3-psycopg`, binaries carried in by hand |

Commit: `git commit -m "terraform: bastion tooling startup script"` → `79f7e64`

- [x] applied (`plan`: No changes)
- [x] tools work: `kubectl get nodes` runs from the bastion (Step 9 proof; the four version lines were not pasted)
- [x] committed

## Step 9 — K3s install + kubeconfig on the bastion

Goal: single-server k3s on the private VM, and `kubectl` on the bastion talking to it over the private network (6443, opened by the Step 4 rule). Flags checked against docs.k3s.io on 2026-10-14.

`k3s/install-k3s.sh` (copied to the VM with scp, run there):
```bash
#!/bin/bash
# Runs ON the k3s VM (copied there with scp). Single server, embedded SQLite.
# Needs Cloud NAT: this VM has no public IP and get.k3s.io is on the internet.
set -euo pipefail

# The bastion talks to the API at this address, so the API certificate must carry it.
# (k3s adds the node IP by itself; explicit means no surprise if the node ever has two.)
NODE_IP="$(hostname -I | awk '{print $1}')"

# --write-kubeconfig-mode 644  : fde can read the kubeconfig, needed for the copy to the bastion
# --disable traefik, servicelb : no ingress, no LoadBalancer. Nothing listens on the node
#                                except SSH and the API (6443). Postgres stays ClusterIP-only.
curl -sfL https://get.k3s.io | sh -s - server \
  --write-kubeconfig-mode 644 \
  --tls-san "${NODE_IP}" \
  --disable traefik \
  --disable servicelb

# The installer returns when the service starts, not when the API answers.
until kubectl get nodes >/dev/null 2>&1; do sleep 2; done
kubectl wait --for=condition=Ready node --all --timeout=120s
kubectl get nodes -o wide
```
Flags: `--write-kubeconfig-mode 644` lets `fde` read `/etc/rancher/k3s/k3s.yaml` (default root-only, trap 5). `--tls-san <node ip>` puts the private IP in the API certificate. `--disable traefik --disable servicelb`: no ingress, no LoadBalancer; nothing listens on the node but SSH and 6443; Postgres stays ClusterIP-only, which is exactly what `validate.py` will assert. Datastore: embedded SQLite; `--cluster-init` converts to etcd in place when HA comes (Step 7 table). Version pin for the on-site: `INSTALL_K3S_VERSION=v1.36.5+k3s1` (what the stable channel gave today).

`k3s/copy-kubeconfig.ps1` (laptop):
```powershell
# Runs on the laptop. Copies the k3s kubeconfig to the bastion, pointed at the node's
# private IP instead of 127.0.0.1. The file is an admin credential: it passes through
# $env:TEMP only because PowerShell pipes would re-encode it, and is deleted at the end.
# Start ssh-agent first (Step 7), or every hop asks for the key passphrase.
$k3sIp = terraform -chdir="$PSScriptRoot\..\terraform" output -raw k3s_private_ip
$tmp   = Join-Path $env:TEMP "kubeconfig"

ssh six-seven-k3s "sed 's/127.0.0.1/$k3sIp/' /etc/rancher/k3s/k3s.yaml > /tmp/kubeconfig"
scp six-seven-k3s:/tmp/kubeconfig $tmp
ssh six-seven-bastion "mkdir -p ~/.kube"
scp $tmp six-seven-bastion:~/.kube/config
ssh six-seven-bastion "chmod 600 ~/.kube/config; kubectl get nodes"

ssh six-seven-k3s "rm -f /tmp/kubeconfig"
Remove-Item $tmp
```
The kubeconfig is the cluster-admin credential. On the bastion it is `~/.kube/config`, mode 600; `kubeconfig*` is gitignored in case. Same pattern as docs.k3s.io: `scp` the file, `sed 's/127.0.0.1/<ip>/'`.

Commands:
```powershell
scp .\k3s\install-k3s.sh six-seven-k3s:~/; ssh six-seven-k3s "bash ~/install-k3s.sh"
.\k3s\copy-kubeconfig.ps1
```

Proof (printed from the bastion, 2026-10-14):
```
NAME            STATUS   ROLES           AGE   VERSION
six-seven-k3s   Ready    control-plane   35s   v1.36.5+k3s1
```

| What breaks | Cause |
|---|---|
| install hangs on `curl get.k3s.io` | NAT off or wrong region (trap 1) |
| `\r: command not found` | script copied with CRLF |
| bastion: `connection refused 10.10.0.3:6443` | firewall rule without 6443, or kubeconfig still `127.0.0.1` |
| bastion: permission denied on `k3s.yaml` | `--write-kubeconfig-mode 644` missing |
| `x509: certificate is valid for ...` | kubeconfig points at an IP that is not in the cert SANs |
| ten passphrase prompts | ssh-agent not running (Step 7 fix) |

Commit: `git commit -m "k3s: install script and kubeconfig copy"` → `3e0380f`

- [x] node Ready, `v1.36.5+k3s1`
- [x] kubeconfig on the bastion, `kubectl get nodes` works there
- [x] committed

## Step 10 — Helm + CNPG operator

Goal: the operator that turns a `Cluster` YAML into running Postgres with replication and failover. Installed with Helm, version pinned. Chart index checked 2026-10-14: chart `0.29.1` = operator `1.30.1`.

`k3s/cnpg-values.yaml` (operator pod only; the Postgres pods get their own requests in the Cluster):
```yaml
replicaCount: 1

# requests = what the scheduler reserves; memory limit = the OOM ceiling.
# No CPU limit on purpose: CPU throttling of the operator only slows failover.
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    memory: 512Mi

# Day 2 (not now): monitoring.podMonitorEnabled: true once Prometheus exists.
```

`k3s/install-cnpg.sh` (runs on the bastion):
```bash
#!/bin/bash
# Runs ON the bastion. Installs the CloudNativePG operator with Helm, pinned.
# Checked 2026-10-14: chart 0.29.1 = operator 1.30.1. Bump on purpose, never "latest".
set -euo pipefail
CHART_VERSION="0.29.1"

helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg

# upgrade --install: one command for the first install and every later upgrade.
# --wait: return only when the operator deployment is ready, so Step 11 can create a Cluster.
helm upgrade --install cnpg cnpg/cloudnative-pg \
  --namespace cnpg-system --create-namespace \
  --version "${CHART_VERSION}" \
  --values "$(dirname "$0")/cnpg-values.yaml" \
  --wait --timeout 5m

kubectl -n cnpg-system get pods
kubectl get crd clusters.postgresql.cnpg.io
```

Three things to defend: `--version` (same bits on site as in practice; `latest` is a surprise waiting to happen), `upgrade --install` (first install and every upgrade are the same command; running it twice is harmless), `--wait` (the script returns only when the operator is Ready, so the next step cannot race it). `helm uninstall` keeps the CRDs on purpose: existing Clusters survive an operator reinstall.

Commands: `scp .\k3s\cnpg-values.yaml .\k3s\install-cnpg.sh six-seven-bastion:~/; ssh six-seven-bastion "bash ~/install-cnpg.sh"` (≈1 min: the node pulls `ghcr.io/cloudnative-pg/cloudnative-pg:1.30.1` through NAT).

| What breaks | Cause |
|---|---|
| operator `ImagePullBackOff`, `--wait` times out | node cannot reach ghcr.io: NAT (trap 1) |
| `Kubernetes cluster unreachable` | `~/.kube/config` missing on the bastion, or still `127.0.0.1` |
| `helm repo add` fails | bastion has no internet; on site: proxy, or `helm pull` the chart and carry it in |
| pod `Pending` | requests do not fit: `describe` says `Insufficient memory` |

Commit: `git commit -m "k3s: cnpg operator via helm, pinned"` → `c385da2`

- [x] committed
- [ ] proof line not pasted: `kubectl -n cnpg-system get pods` → `1/1 Running`

## Step 11 — Postgres `Cluster` airis-core

Goal: the first phase of Airis Core: one CNPG `Cluster`, primary + one streaming replica, explicit resources, internal only. Fields checked against the CNPG docs 2026-10-14.

`k3s/airis-core.yaml` (namespace + Cluster in one file; `kubectl apply` creates them in order):
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: airis-core
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: airis-core
  namespace: airis-core
spec:
  instances: 2
  # No imageName: operator 1.30.1 pulls the PostgreSQL 18 image it was released with.
  # Pin it on site only after `kubectl cnpg status` has shown the tag, so a pin can never miss.

  bootstrap:
    initdb:
      database: airis
      owner: airis   # password generated by the operator into Secret airis-core-app
  # enableSuperuserAccess stays false (default): no postgres password exists anywhere.

  # memory limit == request: no overcommit. No CPU limit: throttling on 2 vCPU hurts more than it protects.
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      memory: 1Gi

  postgresql:
    parameters:
      shared_buffers: "256MB"   # ~25% of the memory limit
      max_connections: "100"

  # Defaults, written out because they are the HA story: today both pods share the only node;
  # the moment a second node joins, the replica moves there. "required" would leave it Pending.
  affinity:
    enablePodAntiAffinity: true
    topologyKey: kubernetes.io/hostname
    podAntiAffinityType: preferred

  # local-path = a folder on the node's disk, node-bound. Data safety comes from streaming
  # replication, not from the volume. HA path: a CSI class (GCE PD).
  storage:
    storageClass: local-path
    size: 5Gi

  primaryUpdateStrategy: unsupervised   # minor upgrades: replicas first, then automatic switchover
  # Day 2 (commented in the file): backup via the barman-cloud plugin to GCS; monitoring.enablePodMonitor.
```

What the operator creates from it: pods `airis-core-1` (primary) and `airis-core-2` (replica), one PVC each, Services `airis-core-rw` (primary), `-ro` (replicas), `-r` (any), all ClusterIP, Secret `airis-core-app` (user `airis`, password, dbname, uri), server certificates (TLS on by default, `hostssl` in `pg_hba`).

`k3s/deploy-airis-core.sh` (bastion): `kubectl apply -f airis-core.yaml`, then polls `.status.phase` and `.status.readyInstances` every 5 s (up to 7.5 min) until `Cluster in healthy state` and `2`, then prints `kubectl cnpg status` and `get pods,svc,pvc`.

Sizing, the one-minute answer when they ask: node 8 GB → OS + k3s ≈ 1.5 GB, operator 0.5 GB, two Postgres pods 1 GB each = 4 GB used, 4 GB headroom. `shared_buffers` 25% of the pod limit; `effective_cache_size` would be ~75% in a dedicated setup. Disk: 5 Gi per instance on a 20 GB node disk; real sizing = rows × row size × index factor × bloat × growth, plus WAL retention (`architecture.md`).

Commands:
```powershell
scp .\k3s\airis-core.yaml .\k3s\deploy-airis-core.sh six-seven-bastion:~/; ssh six-seven-bastion "bash ~/deploy-airis-core.sh"
```
Expected tail: `Status: Cluster in healthy state`, `Instances: 2`, `Ready instances: 2`, one streaming replica in the replication table, pods `airis-core-1` and `airis-core-2` `1/1 Running`, three ClusterIP services, two Bound PVCs.

| What breaks | Cause |
|---|---|
| pod `Pending`, "unbound PersistentVolumeClaims" | storage class name wrong: `kubectl get storageclass` → `local-path` |
| pod `Pending`, "Insufficient memory" | requests do not fit; the node has ~7.6 GB allocatable |
| `ImagePullBackOff` on the postgres image | NAT, or a pinned tag that does not exist |
| `OOMKilled` | limit below real use; raise it, keep `shared_buffers` ≤ 25% |
| stuck at "Setting up primary" | initdb job failed: `kubectl -n airis-core logs job/airis-core-1-initdb` |
| `max_connections: 100` rejected by the API | parameters are strings: quote the number |
| `kubectl cnpg status` not found | Step 8 plugin missing on the bastion |

Commit: `git add k3s/; git commit -m "k3s: airis-core postgres cluster"`

- [ ] applied, `Cluster in healthy state`, 2/2 ready
- [ ] committed

## Step 12 — `validate.py`: the handover artifact

Goal: a script the client's security team can run from the bastion that proves the database is reachable only through approved paths, healthy, replicated, encrypted, and not exposed. Exit code 1 if anything fails, JSON report for the file.

Files: `validate/validate.py` (≈180 lines, stdlib + `psycopg` only), `validate/requirements.txt` (`psycopg[binary]~=3.3`, PyPI 2026-10-14: 3.3.6), `validate/run-validate.ps1` (laptop: scp both to the bastion, run with `/opt/venv/bin/python`, scp `handover_report.json` back; extra args pass through, e.g. `--chaos`).

Structure (explain this on site, not the lines):
1. `kubectl()` wraps `subprocess.run`; non-zero exit raises. `kubectl_json()` adds `-o json`.
2. `check(name, fn)`: runs one check, turns any exception into a FAIL line with the error as evidence. Nothing aborts the run; the client gets a full table every time.
3. Kubernetes checks: API on the private IP (`kubectl config view` server must not be `127.0.0.1`, `/readyz` = ok) → node Ready → CNPG deployment has an available replica → Cluster phase healthy, `readyInstances == instances`, `currentPrimary` set.
4. Credentials from Secret `airis-core-app` (`username`, `password`, `dbname`), base64-decoded, kept in a dict, never logged, never in the report.
5. `port_forward()` context manager: `kubectl port-forward svc/airis-core-rw 15432:5432` as a subprocess, waits until the port accepts TCP, always terminated in `finally`. `psycopg.connect(host=127.0.0.1, sslmode=require, ...)`.
6. DB checks: write/read round trip on a scratch table (dropped afterwards) → `pg_stat_replication` count ≥ instances−1 → `pg_stat_ssl` for the session says encrypted. If the tunnel or login fails, all three are FAIL with the reason.
7. Negative checks: no node advertises an ExternalIP → direct TCP to `<node ip>:5432` from the bastion must *not* connect (timeout = firewall drop, refused = nothing listens; both PASS) → no Service of type NodePort or LoadBalancer in any namespace.
8. `--chaos`: read `currentPrimary`, delete that pod, poll until `currentPrimary` changed and the cluster is healthy with all instances ready; evidence is the number of seconds.
9. Report: `{timestamp, cluster, passed, failed, checks[]}` → `handover_report.json`; `sys.exit(0 or 1)`.

Commands:
```powershell
.\validate\run-validate.ps1
.\validate\run-validate.ps1 --chaos
```
Expected: 10 PASS lines (11 with `--chaos`), `10/10 checks passed`, exit code 0, `validate\handover_report.json` on the laptop.

| What breaks | Cause |
|---|---|
| `ModuleNotFoundError: psycopg` | ran with system python instead of `/opt/venv/bin/python` |
| "port-forward did not come up" | port 15432 busy (`--local-port 15433`) or the API is unreachable |
| TLS check FAIL | `sslmode` missing from the connect call (default `prefer` still encrypts, but say `require`) |
| replication count 0 | replica down: `kubectl cnpg status` |
| direct 5432 check FAIL ("accepted") | something listens on the node: `kubectl get svc -A`, `ss -lntp` on the node |
| chaos: no new primary within 180 s | operator cannot recreate the pod (local-path on one node is fine; check events) |

Commit: `git add validate/; git commit -m "validate: handover script"`

- [ ] all checks PASS, exit 0
- [ ] `--chaos` failover timed
- [ ] committed

## Step 13 — Demo flow, failure playbook, teardown

Written, no cloud changes:
- `docs/demo.md`: the 90-minute run sheet with every command in order, what to say while things install, the 5-minute demo, the NAT-off demo, the teardown, and what to drop when behind schedule.
- `docs/failure-playbook.md`: one command per layer that shows the state; tables for Terraform apply errors, SSH, K3s, the CrashLoopBackOff recipe (`get pods` → `describe` → `logs --previous` → events), CNPG/Postgres, validate.py; resets; time boxes.

NAT-off demo (optional, 2 minutes): `enable_nat = false` in tfvars → `terraform plan` = 2 to destroy → `apply` → `kubectl get cluster -n airis-core` still healthy, `ssh six-seven-k3s "curl -m 5 ifconfig.me"` hangs. Switch back on before anything needs to pull an image.

Teardown, every session:
```powershell
cd terraform; terraform destroy
gcloud compute instances list; gcloud compute routers list
```
Both lists must come back empty. Cost of forgetting: two VMs + NAT ≈ 3 USD/day.

- [ ] demo flow rehearsed once end to end
- [ ] `terraform destroy` clean (plan shows 10 to destroy)

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
- The K3s VM has no public IP. How do you SSH to it from the laptop in one command, without copying the private key to the bastion? → ProxyJump, see Step 7.
- ProxyJump vs agent forwarding vs copying the key. → see Step 7.
- "Suitable for future HA expansion?" The layer table and the no-teardown path. → see Step 7.
- Startup script: `metadata` key (in place) vs `metadata_startup_script` (replaces the VM). → see Step 8.
- Why `--disable traefik --disable servicelb`? Nothing listens on the node but SSH and 6443. → see Step 9.
- Where the kubeconfig lives, why it is a secret, how it got to the bastion without the key leaving the laptop. → see Step 9.
- Why pin the chart, why `upgrade --install`, why `--wait`; why CRDs survive `helm uninstall`. → see Step 10.
- Requests vs limits, why no CPU limit, `shared_buffers` 25%, `preferred` vs `required` anti-affinity, how big is the DB. → see Step 11.
- What the handover script proves and what it must *not* be able to do; why exit codes and JSON. → see Step 12.
- CrashLoopBackOff: the four commands in order, and what each STATUS tells you about the layer. → `docs/failure-playbook.md`.

## Next

Step 11 — apply `airis-core.yaml` from the bastion, paste `kubectl cnpg status`. Then Step 12 `run-validate.ps1`, Step 13 rehearsal + destroy.
