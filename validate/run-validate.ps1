# Runs on the laptop: ships validate.py to the bastion, runs it there (the only place with a
# path to Postgres) and brings the JSON report back. Extra arguments go to validate.py:
#   .\run-validate.ps1            all checks
#   .\run-validate.ps1 --chaos    plus: delete the primary and time the failover
scp "$PSScriptRoot\validate.py" "$PSScriptRoot\requirements.txt" six-seven-bastion:~/
ssh six-seven-bastion "/opt/venv/bin/pip install -q -r ~/requirements.txt && /opt/venv/bin/python ~/validate.py $args"
$code = $LASTEXITCODE
scp six-seven-bastion:~/handover_report.json "$PSScriptRoot\handover_report.json"
exit $code
