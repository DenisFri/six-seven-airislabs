---
name: log
description: Record the just-finished step in docs/build-log.md and docs/plan.md, then mirror the log to the Obsidian note.
disable-model-invocation: true
---

1. Append `## Step N — <title>` to `docs/build-log.md` in the existing style: goal, why, code blocks, commands, a "What breaks | Cause" table, checkboxes with real status. Insert it before `## Before the on-site`.
2. Update the matching row in `docs/plan.md` and the `## Next` line at the end of `docs/build-log.md`.
3. Add any new "say this on site" argument to the `## Think about` list in the log.
4. Copy the full log over the Obsidian note (path in `.claude/rules/docs-sync.md`). Both files must be identical; confirm with a byte count.
5. Commit: `git add docs && git commit -m "docs: step N"`. Show a three-line summary of what was written.
