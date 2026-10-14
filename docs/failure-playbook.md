# Failure playbook

For the on-site, when something breaks. Name the layer first, run the proof command, then fix.
Say out loud what you are doing. If a fix passes 5 minutes: state the workaround, move on, come back at the end.

Layer order is build order: Terraform → SSH → K3s → pods → CNPG/Postgres → validate.py.

## 0. One command per layer that shows the state

| Layer | Command |
|---|---|
| Terraform | `terraform plan` (what differs from the code) · `terraform state list` (what Terraform thinks exists) |
| SSH | `ssh -v six-seven-bastion exit` (the last lines name the reason) |
| K3s service | `ssh six-seven-k3s "sudo systemctl status k3s --no-pager; sudo journalctl -u k3s -n 30 --no-pager"` |
| Pods | `kubectl get pods -A` then `kubectl get events -A --sort-by=.metadata.creationTimestamp \| tail -20` |
| CNPG | `kubectl cnpg status airis-core -n airis-core` |
| Postgres | `kubectl cnpg psql airis-core -n airis-core -- -c "select pg_is_in_recovery()"` (`f` = primary) |

## 1. Terraform apply fails

Read the **first** error only; later ones are consequences. A partial apply is not a disaster: fix, re-run `apply`, it continues (idempotent).

| Error text | Cause | Fix |
|---|---|---|
| could not find default credentials | ADC login missing | `gcloud auth application-default login` |
| API has not been used in project / is disabled | Compute (or IAM) API off | `gcloud services enable compute.googleapis.com iam.googleapis.com`, wait 1 min |
| `ZONE_RESOURCE_POOL_EXHAUSTED` / machine type unavailable | zone has no capacity | change `zone` to another letter (`me-west1-a/b/c`), apply |
| already exists | created by hand or state lost | `terraform import ADDRESS ID`, or delete the stray object in the console |
| Reference to undeclared resource / variable | typo, or file missing | `terraform validate` names the line |
| constraint violated / org policy | external IP or SA restriction | IAP fallback for the bastion; keep going with what applies |
| Quota exceeded | new project limits | smaller machine type, or ask the POC |
| `Error acquiring the state lock` | previous run died | `terraform force-unlock ID` (local state: delete `.terraform.tfstate.lock.info`) |

Never edit `terraform.tfstate` by hand. Tools: `terraform state list`, `state show`, `apply -replace=ADDRESS` (rebuild one resource), `import`.

## 2. SSH

| Symptom | Means | Proof | Fix |
|---|---|---|---|
| connection timed out | packets dropped: firewall | `curl.exe ifconfig.me` vs `mngmt_cidr` in tfvars; `gcloud compute instances describe six-seven-bastion --format="get(tags.items)"` | fix `mngmt_cidr`, `terraform apply` |
| connection refused | reached the host, nothing on 22 | VM still booting | wait 30 s |
| Permission denied (publickey) | reached sshd, auth failed | `ssh -v` shows "Offering public key"; `-i` and `User fde`? | right key, right user; `block-project-ssh-keys` only blocks *project* keys |
| UNPROTECTED PRIVATE KEY FILE | Windows ACL too open | `icacls $HOME\.ssh\airis` | `icacls $HOME\.ssh\airis /inheritance:r /grant:r "$env:USERNAME:R"` |
| hop 2 fails, hop 1 works | bastion → k3s rule or tag | `gcloud compute firewall-rules list --filter="network:six-seven-vpc"` | tag `k3s` on the VM, `source_tags = ["bastion"]` |
| passphrase asked twice per login | no agent | `ssh-add -l` | `Start-Service ssh-agent; ssh-add $HOME\.ssh\airis` |
| Host key changed warning | VM was rebuilt (same IP) | expected after `-replace` | `ssh-keygen -R 34.165.78.24` |

## 3. K3s install

| Symptom | Cause | Fix |
|---|---|---|
| `curl get.k3s.io` hangs | no Cloud NAT, or NAT in another region | `enable_nat = true`, apply; `gcloud compute routers nats list --router=six-seven-router --region=me-west1` |
| `\r: command not found` | script uploaded with CRLF | `sed -i 's/\r$//' install-k3s.sh` on the VM; fix `.gitattributes` later |
| node NotReady for > 2 min | k3s still starting, or CNI | `sudo journalctl -u k3s -n 50` |
| kubectl on bastion: connection refused | kubeconfig still `127.0.0.1`, or 6443 not open | `grep server ~/.kube/config`; firewall rule ports |
| kubectl on bastion: permission denied on k3s.yaml | installed without `--write-kubeconfig-mode 644` | `sudo chmod 644 /etc/rancher/k3s/k3s.yaml` |
| x509: certificate is valid for … | kubeconfig IP not in the API cert | use the node IP (it is in the SANs); `--tls-san` for anything else |

Reset: `ssh six-seven-k3s "/usr/local/bin/k3s-uninstall.sh"`, re-run the install script (2 min).

## 4. Pods: the CrashLoopBackOff recipe (they test this)

1. `kubectl get pods -A`. The STATUS names the layer:
   `ImagePullBackOff` / `ErrImagePull` → network (NAT) or wrong tag · `Pending` → scheduling: resources or PVC · `CrashLoopBackOff` / `Error` → the process itself · `Init:…` → an init container (CNPG bootstrap/join) · `OOMKilled` shows under "Last State" in describe.
2. `kubectl -n NS describe pod POD`: read **Events** at the bottom, and **Last State** (exit 137 = killed for memory, 1 = application error).
3. `kubectl -n NS logs POD --previous`: the log of the container that crashed, not of the restart.
4. `kubectl -n NS get events --sort-by=.metadata.creationTimestamp`.
5. CNPG extra: `kubectl -n airis-core describe cluster airis-core` (conditions), `kubectl cnpg status airis-core -n airis-core`, bootstrap job logs: `kubectl -n airis-core logs job/airis-core-1-initdb`.

| Symptom | Cause | Fix |
|---|---|---|
| `ImagePullBackOff` | no NAT / wrong tag | NAT on; `describe` shows the exact image name |
| `Pending`, event "Insufficient memory/cpu" | requests too big for the node | lower `resources.requests`, or `e2-standard-2` |
| `Pending`, event "unbound PersistentVolumeClaims" | storage class name wrong | `kubectl get storageclass` → `local-path`; `kubectl -n airis-core get pvc` |
| `OOMKilled` | memory limit below real use | raise `limits.memory`; keep `shared_buffers` ≤ 25% of it |
| `CrashLoopBackOff` in postgres container | bad `postgresql.parameters` | `logs --previous` shows the parameter; fix manifest, apply |
| cluster stuck "Setting up primary" | initdb job failed | job logs; usually storage or parameters |
| cluster stuck "Creating a new replica" | join job cannot pull or no space | job logs; `df -h` on the node |
| operator pod restarting | webhook / RBAC on reinstall | `kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg` |

## 5. Postgres and CNPG

| Symptom | Cause | Fix |
|---|---|---|
| `Cluster in healthy state` but `validate.py` round trip fails | tunnel or login | `kubectl -n airis-core get secret airis-core-app`; port-forward by hand and `psql -h 127.0.0.1 -p 15432` |
| replication count 0 | replica not streaming | `kubectl cnpg status` "Streaming Replication status"; replica pod logs |
| `-ro` connection refused | no replica ready | `kubectl -n airis-core get pods` |
| failover takes > 60 s | replica far behind, or pod recreate slow on local-path | `kubectl cnpg status`, events; acceptable: say the number, explain |
| password authentication failed | secret rotated or wrong user | read the secret again; user is the `owner` from initdb |

Resets: `kubectl delete cluster airis-core -n airis-core` removes pods and PVCs (owned by the Cluster), re-apply = 3 minutes. Worst case: `terraform apply -replace=google_compute_instance.k3s`, re-run the k3s and CNPG scripts.

## 6. validate.py

| Symptom | Cause | Fix |
|---|---|---|
| `ModuleNotFoundError: psycopg` | ran with system python | `/opt/venv/bin/python validate.py` |
| `externally-managed-environment` | pip outside the venv | `/opt/venv/bin/pip install -r requirements.txt` |
| "port-forward did not come up" | port 15432 busy, or kubectl cannot reach the API | `--local-port 15433`; check `kubectl get nodes` first |
| TLS check fails | `sslmode` dropped from the connect call | `sslmode="require"` |
| direct 5432 check PASSES on refused, FAILS on accepted | that is correct: accepted means something listens on the node | find it: `kubectl get svc -A`, `ss -lntp` on the node |
| every DB check fails, cluster healthy | wrong namespace or cluster name | `--namespace`, `--cluster` |

## 7. Time boxes

- Up to 5 minutes on any single failure. Then: state cause, workaround, and continue.
- A FAIL in the handover report is still a result. Explain it; do not hide it.
- Last 5 minutes are for the demo, no matter what state the build is in.
