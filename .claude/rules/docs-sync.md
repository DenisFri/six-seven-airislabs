# Documentation rule (loads every session)

- After every finished step, run `/log`: append the step to `docs/build-log.md` in the existing style (goal, why, code, commands, "what breaks | cause" table, checkboxes with real status), update `docs/plan.md`, then copy the full `docs/build-log.md` over the Obsidian note so both stay identical:
  `C:\Users\denis\Documents\Obsidian\JobSearch\Airis Labs\Six Seven Project.md`
  (Git Bash path: `/c/Users/denis/Documents/Obsidian/JobSearch/Airis Labs/Six Seven Project.md`)
- If that path does not exist on this machine, ask Denis for the right one and update this file.
- Docs never contain secrets: no private keys, no tfstate content, no passwords, no kubeconfig. Public IPs and project IDs are fine.
- Drill and quiz results go to `docs/drills.md`.
- Committing docs is fine without asking: `git add docs && git commit -m "docs: step N"`.
