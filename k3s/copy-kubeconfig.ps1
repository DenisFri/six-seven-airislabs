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
