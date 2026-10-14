<#
.SYNOPSIS
  Tears Six Seven down: terraform destroy, proof that the project is empty, SSH cleanup on this laptop.
  Run at the end of every practice session, and on site only if the client wants the project clean.

.EXAMPLE
  .\scripts\down.ps1                 # terraform asks for "yes"
  .\scripts\down.ps1 -AutoApprove
#>
[CmdletBinding()]
param([switch]$AutoApprove)
$ErrorActionPreference = "Stop"
$Tf = (Resolve-Path (Join-Path $PSScriptRoot "..\terraform")).Path

function Out-Cmd {
  param([scriptblock]$Command)
  $ErrorActionPreference = "Continue"
  & $Command 2> $null
}

# The outputs vanish with the resources, so read the IPs first (needed for the known_hosts cleanup).
$ips = @(Out-Cmd { terraform -chdir="$Tf" output -raw bastion_public_ip }) + @(Out-Cmd { terraform -chdir="$Tf" output -raw k3s_private_ip })

Write-Host "`n=== terraform destroy" -ForegroundColor Cyan
if ($AutoApprove) { terraform -chdir="$Tf" destroy -auto-approve } else { terraform -chdir="$Tf" destroy }
if ($LASTEXITCODE -ne 0) { throw "destroy failed: read the first error, fix it, run again (destroy is idempotent)" }

Write-Host "`n=== proof: nothing left in the project (all three lists must be empty)" -ForegroundColor Cyan
gcloud compute instances list --format="table(name,zone,status)"
gcloud compute routers list --format="table(name,region)"
gcloud compute networks list --filter="name=six-seven-vpc" --format="table(name)"

Write-Host "`n=== local cleanup: SSH aliases and host keys of VMs that no longer exist" -ForegroundColor Cyan
$cfg = Join-Path $HOME ".ssh\config"
if (Test-Path $cfg) {
  $keep = ((Get-Content $cfg -Raw) -split '(?m)^(?=Host\s)') | Where-Object { $_ -notmatch '^Host\s+six-seven-' }
  Set-Content -Path $cfg -Value (($keep -join "").TrimEnd() + "`n") -Encoding ascii
}
foreach ($ip in $ips) { if ($ip) { Out-Cmd { ssh-keygen -R $ip } | Out-Null } }
Write-Host "DOWN. Kept: terraform.tfstate (now empty), terraform.tfvars (project id + office IP, no secrets), the SSH key." -ForegroundColor Green
