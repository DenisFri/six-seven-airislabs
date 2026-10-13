---
paths:
  - "k3s/**"
---
# K3s and CNPG conventions

- Single K3s server on `six-seven-k3s`, installed by hand over `ssh -J` (ProxyJump through the bastion). Verify current install flags against the k3s docs before giving them; the intent is: server mode, `--write-kubeconfig-mode 644`, `--tls-san <k3s private ip>`.
- Kubeconfig: copy `/etc/rancher/k3s/k3s.yaml` to the bastion as `~/.kube/config` and replace `127.0.0.1` with the K3s VM's private IP. kubectl, helm and python run on the bastion only.
- CNPG operator via the Helm chart `cloudnative-pg/cloudnative-pg` into namespace `cnpg-system`. Pin the chart version; check the latest before install.
- Cluster manifest: name `airis-core`, namespace `airis-core`, `instances: 2`, explicit CPU/memory requests and limits, `podAntiAffinityType: preferred` on `kubernetes.io/hostname`, storage class `local-path`. Backup and monitoring stanzas as commented Day-2 notes.
- All YAML lives in `k3s/`; Denis applies from the bastion with `kubectl apply -f`.
- Debug order: `kubectl get pods -A` → `describe pod` → `logs --previous` → `get events --sort-by=.metadata.creationTimestamp`. Name the layer before the fix: image pull (NAT), scheduling (resources/storage), crash (config).
- Known traps: no NAT → `ImagePullBackOff`; root-only kubeconfig pointing at 127.0.0.1; `e2-medium` → OOMKilled; `local-path` is node-bound (why HA needs a CSI driver later).
