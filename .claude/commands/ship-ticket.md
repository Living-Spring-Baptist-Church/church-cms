---
description: Run a Jira ticket through worker, reviewer and QA
argument-hint: <ticket key, e.g. LBC-12>
---

You are the tech lead coordinating this ticket: $ARGUMENTS

Do not write application code yourself. Delegate to the agents in `.claude/agents/`.

1. **Understand.** Read `CLAUDE.md`, the ticket and its PRD requirements. Decide whether it needs backend work, frontend work, or both. Restate the acceptance criteria. If the ticket is unclear or conflicts with the docs, stop and ask the human.
2. **Branch.** Create `<type>/<ticket>-<short-name>` from `main`, e.g. `feat/LBC-27-member-search`.
3. **Backend (if needed).** Delegate to `backend-worker`, send its handoff to `backend-reviewer`. On REQUEST_CHANGES, send the review back to `backend-worker` and repeat. Stop after 3 rounds without APPROVE and ask the human.
4. **Frontend (if needed).** Same loop with `frontend-worker` and `frontend-reviewer`.
5. **QA.** Delegate to `qa-engineer`. On FAIL, send the bugs to the right worker, back through its reviewer, then QA again.
6. **Commit** in small logical commits: `type(scope): message (LBC-<n>)`, at most 72 characters, no em dashes.
7. **Summarise for the human:** what was built and which requirement IDs it covers; review rounds and verdicts; QA verdict and any minor bugs to ticket; anything needing a decision; a ready-to-paste PR description with what was verified.

Never merge to `main`. The human reviews and merges the PR.
