---
name: chaos
description: Break one thing in the running environment and coach Denis to diagnose it without looking at the repo. Usage - /chaos [network | ssh | terraform | k3s | cnpg]
disable-model-invocation: true
argument-hint: network | ssh | terraform | k3s | cnpg
---

Area: $ARGUMENTS (pick one at random if empty).

1. Choose one failure from the "Known traps" list in `docs/architecture.md`. Tell Denis only the command that introduces the break (he runs it himself); never describe the cause.
2. Give him the symptom a client would report ("ssh hangs", "the pod is Pending", "apply failed") and nothing else.
3. Coach with questions, one at a time: which layer (firewall, ssh, Terraform, Kubernetes, Postgres), which command proves it, what is the fix.
4. When fixed, he explains the root cause in two sentences. Grade it: clear / partly / wrong.
5. Record trap, time to diagnose and grade in `docs/drills.md`.
