---
name: optio-refresh-guides
description: Bring the agent guides (nested AGENTS.md / CLAUDE.md files, docs/agent-guides, MANIFEST.md, skills, docs/airgap/gotchas.md) back in step with the code after an upstream sync, a refactor or moved files. Use when scripts/check-agent-guides.sh reports MISSING or INFO lines, or after any upstream merge.
---

# Refresh the agent guides

The guides are the agents' memory of the codebase. A wrong path costs every later session time.
Edit the guides in this repo; if the team keeps the optio-agent-kit repo, copy changes back with its
harvest.sh afterwards.

## 1. Measure

```bash
bash scripts/check-agent-guides.sh
```

- `MISSING <guide> → <path>`: a named file moved or was deleted.
- `MISSING IMPORT`: a `CLAUDE.md` imports a file that is gone.
- `INFO service modules not in …`: new files in `apps/api/src/services/` the index doesn't mention.
- Site facts still empty? `grep -c '<FILL' docs/airgap/site-facts.md` (the team fills them).

- `STALE helm/VALUES-MAP.md`: the chart or the env vars the code reads changed. Run
  `bash scripts/helm-value-map.sh` and read the diff (`git diff helm/VALUES-MAP.md`): new rows are new
  settings, rows that moved to "never sets" are settings the chart dropped.

## 2. Fix missing paths

For each MISSING path find where it went: `git log --diff-filter=R --summary -5 -- '<old path>'` or
`git ls-files | grep <file name>`. Update the guide line. If the thing no longer exists, delete the line.

## 3. Index new service modules

Read the first comment block of each new module (`head -30 apps/api/src/services/<name>.ts`) and add it to the
matching group in `apps/api/src/services/AGENTS.md`. Unsure → the "Plumbing" group.

## 4. Re-check the main ideas (only after an upstream merge)

`OLD` = the previous upstream base commit (`docs/airgap/site-facts.md`), `upstream-main` = the merged upstream ref.

```bash
git diff --stat "$OLD" upstream-main -- apps packages helm images scripts | tail -20
git diff "$OLD" upstream-main -- AGENTS.md | head -300
```

For each area with large changes, read its `AGENTS.md` "Main ideas" and fix what is no longer true (a renamed
concept, a new worker, a new run kind). New rules every agent must follow go into the root `CLAUDE.md`
(keep it under ~120 lines). Keep each area guide under ~120 lines: short beats complete.

## 5. Re-check the air-gap notes

For every item in `docs/airgap/gotchas.md` and the chart notes in `helm/CLAUDE.md`: grep the code to see
whether upstream fixed it. Fixed → delete the item and note it in the worklog. The "never sets" section of
`helm/VALUES-MAP.md` shows at a glance whether the chart gained a value for `GITLAB_HOSTS` and friends.

## 6. Done

`bash scripts/check-agent-guides.sh` ends with `0 missing`. Add a worklog Log line:
`YYYY-MM-DD · guides · fixed <n> paths, indexed <n> modules, updated <areas>`
