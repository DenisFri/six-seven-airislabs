---
name: step
description: Continue the Six Seven build with the next step from docs/plan.md, in coaching mode.
disable-model-invocation: true
---

1. Read `docs/plan.md` and the last two sections of `docs/build-log.md`.
2. Tell Denis in two lines where we are and what the next step builds.
3. Run the step in the coaching rhythm (`.claude/rules/coaching.md`): goal → why → code he types → what usually breaks → verify command → commit message.
4. State the expected `terraform plan` summary (or the expected kubectl output) before he runs anything.
5. Do not start the following step until Denis pastes proof. When proof arrives, offer `/log`.
