# The air-gapped fork — what it is and what we are doing

## Why this fork exists

We run Optio inside an air-gapped network so teams can hand work to coding agents:
a ticket or a request becomes an agent run in a pod, which opens a merge request on our GitLab.
Upstream Optio assumes the internet (GitHub, Jira Cloud, public registries, public model APIs).
Our environment has none of that, so we carry a small set of changes and a disciplined way of working.

## Our environment, in one table

| Upstream assumes                 | We have                                                                                            |
| -------------------------------- | -------------------------------------------------------------------------------------------------- |
| Internet for images and packages | an internal registry, filled from an offline kit brought in through your approved transfer process |
| GitHub                           | self-managed GitLab (private CA, possibly a non-443 port)                                          |
| Jira Cloud                       | our Jira (flavor and version in `docs/airgap/site-facts.md`)                                       |
| Anthropic / OpenAI APIs          | a LiteLLM gateway: a small fast model and a contract Claude model                                  |
| A managed Kubernetes             | Rancher                                                                                            |
| A coding assistant with internet | Claude Code inside the gap, mostly on a small fast model                                           |

## What the fork is made of

1. **Upstream Optio** at the commit in `docs/airgap/site-facts.md`.
2. **Fork patches** — the smallest changes that make Optio work here. Every one is marked
   `AIRGAP-FORK:` in the code (`git grep -n "AIRGAP-FORK"` lists them). Generic ones are candidates for upstream.
3. **Agent guides** (optio-agent-kit): nested `AGENTS.md` files with each area's main ideas (generic,
   upstreamable) plus this fork's layer: the root `CLAUDE.md` router, skills, the scout agent, `docs/airgap/`.
4. **Team-owned state**: `docs/airgap/site-facts.md` (our values) and `docs/airgap/worklog.md`
   (what we are doing now, decisions, log). Kit updates never overwrite these two.

## How we work (the loop)

1. **Diagnose** with a skill: `optio-debug-gitlab`, `optio-debug-jira`, `optio-debug-live`. Evidence first.
2. **Decide** config vs code. Most air-gap failures are config (`docs/airgap/gotchas.md`); only code gets patched.
3. **Patch** minimally, mark `AIRGAP-FORK:`, add or extend the test next to the file.
4. **Check** targeted tests and types; run `bash scripts/airgap/impact.sh` to see what must be rebuilt.
5. **Ship** with skill `optio-rebuild-publish`: offline build, new tag, push, `helm upgrade`, recycle agent pods.
6. **Record** one line in `docs/airgap/worklog.md` — so the next session (human or agent) knows.

## Principles

- No internet, ever, from tools or agents. New dependencies arrive only through a new offline kit.
- Never reuse an image tag. Never print secrets. Never edit the team-owned files from a kit update.
- Prefer config over code, and upstream-able code over fork-only code.
- Agents have no memory between sessions: the worklog and these guides are the memory. Keep them true
  (`bash scripts/check-agent-guides.sh`, skill `optio-refresh-guides`).
