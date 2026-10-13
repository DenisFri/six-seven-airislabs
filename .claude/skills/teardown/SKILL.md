---
name: teardown
description: End-of-session checklist so nothing keeps costing money and the docs are in sync.
disable-model-invocation: true
---

1. Ask Denis to run in `terraform\`: `terraform destroy` (he types `yes`).
2. Then: `gcloud compute instances list`, `gcloud compute routers list --regions=me-west1`, `gcloud compute addresses list`. All three should be empty. If something is left, name the Terraform resource and the command to remove it.
3. Check `git status` is clean and the docs were synced with `/log`.
4. Confirm the `## Next` line in `docs/build-log.md` and the status in `docs/plan.md` point at the right next step.
