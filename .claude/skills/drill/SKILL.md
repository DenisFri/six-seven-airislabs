---
name: drill
description: Timed rebuild drill of one area from a blank folder, from memory. Usage - /drill terraform | k3s | cnpg | python | full
disable-model-invocation: true
argument-hint: terraform | k3s | cnpg | python | full
---

Area: $ARGUMENTS (ask if empty).

1. Denis creates `drills/<area>-<yyyymmdd>/` (gitignored) and writes everything there from memory. Note the start time.
2. Targets: terraform 20 min to a green `plan`; k3s 10 min to `kubectl get nodes` Ready from the bastion; cnpg 15 min to `Cluster in healthy state`; python 25 min to all checks passing; full 90 min end to end with narration.
3. During the drill: show no code. Give hints only when asked, one at a time, and say "hint used" each time.
4. At the end: diff the drill files against the real ones, list every miss, and record time, hints used and misses in `docs/drills.md`.
5. Rule of done: the target time beaten twice in a row with zero hints.
