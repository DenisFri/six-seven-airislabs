<#
.SYNOPSIS
  Brings Six Seven up on a fresh laptop and a fresh GCP project, phase by phase.
  Every phase is the same block of commands as in docs/demo.md; this file only orders them,
  waits where the cloud needs time, and stops on the first error.

.EXAMPLE
  .\scripts\up.ps1 -ProjectId airislabs-six-seven        # everything; shows the plan and asks before apply
  .\scripts\up.ps1 -From k3s                             # continue from a phase after a fix
  .\scripts\up.ps1 -Only validate                        # one phase
  .\scripts\up.ps1 -ProjectId X -Region europe-west1 -Zone europe-west1-b
#>
[CmdletBinding()]
param(
  [string]$ProjectId,
  [string]$Region,
  [string]$Zone,
  [ValidateSet("prereqs", "gcloud", "key", "tfvars", "terraform", "sshconfig", "tools", "k3s", "cnpg", "postgres", "validate")]
  [string]$From = "prereqs",
  [ValidateSet("prereqs", "gcloud", "key", "tfvars", "terraform", "sshconfig", "tools", "k3s", "cnpg", "postgres", "validate")]
  [string]$Only,
  [switch]$AutoApprove
)
$ErrorActionPreference = "Stop"
$Repo   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Tf     = Join-Path $Repo "terraform"
$Phases = @("prereqs", "gcloud", "key", "tfvars", "terraform", "sshconfig", "tools", "k3s", "cnpg", "postgres", "validate")

function Step($text) { Write-Host "`n=== $text" -ForegroundColor Cyan }

function Run {
  # Native commands never throw in PowerShell; this turns any non-zero exit into a stop.
  param([scriptblock]$Command)
  & $Command
  if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE from: $Command" }
}

function Test-Cmd {
  # True when a native command exits 0. Output is discarded; used for probes.
  param([scriptblock]$Command)
  $ErrorActionPreference = "Continue"
  & $Command *> $null
  return ($LASTEXITCODE -eq 0)
}

function Out-Cmd {
  # Stdout of a native command, stderr dropped, never throws.
  param([scriptblock]$Command)
  $ErrorActionPreference = "Continue"
  & $Command 2> $null
}

function Wait-Until {
  param([string]$What, [scriptblock]$Test, [int]$TimeoutSec = 300, [int]$EverySec = 10)
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if (& $Test) { Write-Host "  ok: $What"; return }
    Write-Host "  waiting for $What ..."
    Start-Sleep -Seconds $EverySec
  }
  throw "timeout after ${TimeoutSec}s waiting for $What"
}

$Do = @{}

$Do.prereqs = {
  Step "prereqs: tools on this laptop"
  foreach ($tool in "gcloud", "terraform", "ssh", "scp", "ssh-keygen", "curl.exe") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      throw "$tool not found. Windows: winget install Google.CloudSDK Hashicorp.Terraform (ssh ships with Windows 10+)"
    }
  }
  Run { terraform version }
  Run { gcloud version }
}

$Do.gcloud = {
  Step "gcloud: login, project, ADC for Terraform, APIs"
  if (-not (Out-Cmd { gcloud auth list --filter=status:ACTIVE --format="value(account)" })) { Run { gcloud auth login } }
  if (-not $script:ProjectId) { $script:ProjectId = Out-Cmd { gcloud config list --format="value(core.project)" } }
  if (-not $script:ProjectId) { throw "pass -ProjectId (the project ID, not the name)" }
  Run { gcloud config set project $script:ProjectId }
  # Terraform reads the second credential file, not the gcloud login (trap 2).
  if (-not (Test-Cmd { gcloud auth application-default print-access-token })) { Run { gcloud auth application-default login } }
  if (-not (Test-Cmd { gcloud services enable compute.googleapis.com iam.googleapis.com })) {
    Write-Warning "could not enable the APIs (no permission?). If the client enabled them already, this is fine."
  }
  Run { gcloud config list }
}

$Do.key = {
  Step "key: one ed25519 key for this engagement, loaded into ssh-agent"
  $key = Join-Path $HOME ".ssh\airis"
  New-Item -ItemType Directory -Force (Join-Path $HOME ".ssh") | Out-Null
  if (-not (Test-Path $key)) { Run { ssh-keygen -t ed25519 -f $key -C airis-fde } }
  try {
    $svc = Get-Service ssh-agent -ErrorAction Stop
    if ($svc.StartType -eq "Disabled") { Set-Service ssh-agent -StartupType Manual }
    if ($svc.Status -ne "Running") { Start-Service ssh-agent }
    if ("$(Out-Cmd { ssh-add -l })" -notmatch "airis-fde") { Run { ssh-add $key } }
  } catch {
    Write-Warning "ssh-agent unavailable ($($_.Exception.Message)). Run once as admin: Set-Service ssh-agent -StartupType Manual. Until then you type the passphrase per hop."
  }
}

$Do.tfvars = {
  Step "tfvars: project id, office IP as the only /32 allowed to SSH, NAT on for bootstrap"
  $file = Join-Path $Tf "terraform.tfvars"
  if (Test-Path $file) { Write-Host "  exists, keeping it:"; Get-Content $file; return }
  if (-not $script:ProjectId) { throw "pass -ProjectId" }
  $ip = (curl.exe -s https://ifconfig.me).Trim()
  if ($ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "could not read the public IP (got '$ip')" }
  $lines = @(
    "project_id = `"$script:ProjectId`"",
    "mngmt_cidr = `"$ip/32`"",
    "enable_nat = true   # bootstrap needs egress; false afterwards for zero egress"
  )
  if ($Region) { $lines += "region     = `"$Region`"" }
  if ($Zone)   { $lines += "zone       = `"$Zone`"" }
  Set-Content -Path $file -Value $lines -Encoding ascii
  Get-Content $file
}

$Do.terraform = {
  Step "terraform: init, fmt, validate, plan, apply"
  Run { terraform -chdir="$Tf" init -input=false }
  Run { terraform -chdir="$Tf" fmt }
  Run { terraform -chdir="$Tf" validate }
  Run { terraform -chdir="$Tf" plan -input=false -out=tfplan }
  if (-not $AutoApprove) {
    if ((Read-Host "Apply this plan? [y/N]") -notmatch '^[yY]') { throw "stopped before apply" }
  }
  Run { terraform -chdir="$Tf" apply -input=false tfplan }
  Remove-Item (Join-Path $Tf "tfplan") -ErrorAction SilentlyContinue   # holds variable values; never commit it
  Run { terraform -chdir="$Tf" output }
}

$Do.sshconfig = {
  Step "sshconfig: host aliases from the outputs, stale host keys purged, wait for sshd"
  $bastionIp = Out-Cmd { terraform -chdir="$Tf" output -raw bastion_public_ip }
  $k3sIp     = Out-Cmd { terraform -chdir="$Tf" output -raw k3s_private_ip }
  if (-not $bastionIp -or -not $k3sIp) { throw "no outputs yet; run the terraform phase first" }
  $cfg = Join-Path $HOME ".ssh\config"
  $old = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { "" }
  # An SSH config is a list of "Host" blocks: drop earlier six-seven blocks, keep everything else.
  $keep = ($old -split '(?m)^(?=Host\s)') | Where-Object { $_ -notmatch '^Host\s+six-seven-' }
  $block = @"
Host six-seven-bastion
  HostName $bastionIp
  User fde
  IdentityFile ~/.ssh/airis
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new

Host six-seven-k3s
  HostName $k3sIp
  User fde
  IdentityFile ~/.ssh/airis
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ProxyJump six-seven-bastion
"@
  Set-Content -Path $cfg -Value (($keep -join "").TrimEnd() + "`n`n" + $block) -Encoding ascii
  # A rebuilt VM has a new host key behind the same IP; the old entry would block the connection.
  foreach ($ip in $bastionIp, $k3sIp) { Out-Cmd { ssh-keygen -R $ip } | Out-Null }
  Wait-Until "ssh to the bastion"                      { Test-Cmd { ssh -o ConnectTimeout=5 six-seven-bastion exit } } 180 10
  Wait-Until "ssh to the k3s node through the bastion" { Test-Cmd { ssh -o ConnectTimeout=5 six-seven-k3s exit } }    120 10
}

$Do.tools = {
  Step "tools: the bastion installs kubectl, helm, cnpg plugin and the python venv at first boot"
  $ready = { Test-Cmd { ssh six-seven-bastion "/opt/venv/bin/python -c 'import psycopg' && test -x /usr/local/bin/kubectl && test -x /usr/local/bin/helm" } }
  try { Wait-Until "bastion tooling (startup script, first boot)" $ready 360 15 }
  catch {
    Write-Warning "startup script did not finish by itself; running it by hand"
    Run { ssh six-seven-bastion "sudo google_metadata_script_runner startup" }
    Wait-Until "bastion tooling" $ready 60 10
  }
  Run { ssh six-seven-bastion "kubectl version --client; helm version --short; kubectl cnpg version" }
}

$Do.k3s = {
  Step "k3s: single server on the private node, kubeconfig to the bastion"
  Run { scp (Join-Path $Repo "k3s\install-k3s.sh") "six-seven-k3s:~/" }
  Run { ssh six-seven-k3s "bash ~/install-k3s.sh" }
  Run { & (Join-Path $Repo "k3s\copy-kubeconfig.ps1") }
}

$Do.cnpg = {
  Step "cnpg: operator via helm, chart version pinned"
  Run { scp (Join-Path $Repo "k3s\cnpg-values.yaml") (Join-Path $Repo "k3s\install-cnpg.sh") "six-seven-bastion:~/" }
  Run { ssh six-seven-bastion "bash ~/install-cnpg.sh" }
}

$Do.postgres = {
  Step "postgres: Cluster airis-core, primary + replica, wait for healthy"
  Run { scp (Join-Path $Repo "k3s\airis-core.yaml") (Join-Path $Repo "k3s\deploy-airis-core.sh") "six-seven-bastion:~/" }
  Run { ssh six-seven-bastion "bash ~/deploy-airis-core.sh" }
}

$Do.validate = {
  Step "validate: the handover script, report comes back to validate\handover_report.json"
  Run { & (Join-Path $Repo "validate\run-validate.ps1") }
}

$list = if ($Only) { @($Only) } else { $Phases[([array]::IndexOf($Phases, $From))..($Phases.Count - 1)] }
$t0 = Get-Date
try {
  foreach ($phase in $list) { $script:Current = $phase; & $Do[$phase] }
} catch {
  Write-Host "`nFAILED in phase '$Current': $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "Fix it (docs\failure-playbook.md), then continue with:  .\scripts\up.ps1 -From $Current"
  exit 1
}
Write-Host "`nUP in $([int]((Get-Date) - $t0).TotalMinutes) min. Demo: docs\demo.md (85-90). Teardown: .\scripts\down.ps1" -ForegroundColor Green
