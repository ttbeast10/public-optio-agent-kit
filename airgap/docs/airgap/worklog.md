# Worklog — what we are doing

Owned by the team. The kit installs this file once and never overwrites it.
Agents: read "Now" and "Decisions" before a task; add one line to "Log" after it.
Keep "Now" under 10 lines; move finished items to "Log". No secret values, no hostnames that aren't
already in `docs/airgap/site-facts.md`.

## Now

- Optio runs inside the air gap. Making it work end to end with our GitLab and our Jira.
- GitLab compatibility: issues seen after the move (details to fill as they are diagnosed; skill `optio-debug-gitlab`).
- Jira compatibility: issues seen after the move. Code review (2026-11-02): upstream supports Jira Cloud only
  (REST v3, email + API token). If ours is Server/DC, a fork patch is needed (plan in skill `optio-debug-jira`).
- Agent tooling: Claude Code with a small fast model got slow and messy in this repo → agent kit installed.

## Decisions

- 2026-11-02 · Agent guides: root `CLAUDE.md` is a small router instead of importing the 67 KB root `AGENTS.md`;
  each folder has an `AGENTS.md` with its main ideas; skills hold the runbooks.
- 2026-11-02 · Every fork-only change is marked `AIRGAP-FORK:` and kept minimal.
- 2026-11-02 · Every build gets a new image tag; tags are never re-pushed.

## Open questions

- Jira flavor and version? (fill `docs/airgap/site-facts.md`)
- How do agent pods reach LiteLLM today (pod secret `ANTHROPIC_BASE_URL`, a connection, or a patch)? See `docs/airgap/gotchas.md` §6.
- Which GitLab failures are config (hosts, tokens, CA, outbound allow-list) and which need code?

## Log

<!-- newest first: YYYY-MM-DD · who/agent · what changed · where · result -->

- 2026-11-02 · optio-agent-kit · worklog created by the kit install · docs/airgap · next: fill site-facts.md, run scripts/check-agent-guides.sh
