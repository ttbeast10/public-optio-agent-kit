---
name: optio-sync-upstream
description: Merge a new upstream Optio version (brought into the air gap as a git bundle) into our fork — know our AIRGAP-FORK patches, merge, resolve conflicts, check whether a new offline kit is needed, refresh the agent guides, test the patches, rebuild. Use when a new upstream bundle arrives.
---

# Sync upstream into the fork (inside the air gap)

Upstream moves fast (~345 commits in October 2026). Sync in one sitting, on a branch.
Read `docs/airgap/worklog.md` "Now" first. Someone on an internet-connected host makes the bundle:
`git clone --mirror https://github.com/jonwiggins/optio && git -C optio.git bundle create optio.bundle main`
and brings it in through your approved transfer process, with a new offline kit when dependencies changed.

## 1. Import the bundle

```bash
git bundle verify /path/to/optio.bundle
git fetch /path/to/optio.bundle main:upstream-main
OLD=$(git merge-base HEAD upstream-main)
git log --oneline "$OLD"..upstream-main | wc -l      # how many commits come in
git switch -c sync/$(date +%Y%m%d)
```

## 2. Know our patches before merging

- `git grep -n "AIRGAP-FORK"` → every fork-only change. Write the list down.
- `git diff upstream-main...HEAD --stat` → every file we differ in (patches + agent kit + docs/airgap).

## 3. Merge

`git merge upstream-main`

- Root `CLAUDE.md` conflict → keep ours: `git checkout --ours CLAUDE.md && git add CLAUDE.md`.
- `docs/airgap/*`, `scripts/airgap/*`, nested `AGENTS.md` files we added: upstream doesn't have them, no conflict
  unless upstream adds its own — then keep both: put upstream's text first, ours after, and tell the user.
- Conflict inside an `AIRGAP-FORK` block: take upstream's version, then re-apply our intent. First check whether
  upstream now solves the same problem — if yes, drop our patch and note it in the worklog.
- Never resolve by deleting upstream code you don't understand. Stop and report the conflict.

## 4. Does this need a new offline kit?

`git diff --name-only "$OLD" upstream-main -- package.json pnpm-lock.yaml patches '*/package.json'`
Non-empty → a kit made at the new revision must be loaded (`scripts/offline/load-kit.sh`) before any build.
No kit available → STOP and tell the user.

## 5. Refresh the guides

Run skill `optio-refresh-guides` (it uses `bash scripts/check-agent-guides.sh` and the upstream diff).

## 6. Test our patches

For every package with an `AIRGAP-FORK` change: `pnpm --filter @optio/<pkg> typecheck && pnpm --filter @optio/<pkg> test`.

## 7. Rebuild everything

A new upstream version changes every image: skill `optio-rebuild-publish` with
`--only api,web,agent-base,agent-dind` plus every preset in `scripts/offline/presets.txt`.
Update "Upstream base commit" in `docs/airgap/site-facts.md`.

## 8. Record

Add to `docs/airgap/worklog.md` Log:
`YYYY-MM-DD · sync · upstream <OLD> → <new> (<n> commits) · patches kept/dropped/reworked · kit new/same · guides fixed <n>`
