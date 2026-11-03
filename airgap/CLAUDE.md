<!--
AIR-GAPPED FORK ROUTER (from optio-agent-kit, layer "airgap").
Replaces upstream's one-line `@AGENTS.md` import on purpose: the root AGENTS.md is ~67 KB (~30k tokens)
and drowns small models. Keep this file under ~120 lines.
- Site values live in docs/airgap/site-facts.md (imported below), current work in docs/airgap/worklog.md.
  Both are owned by the team: kit updates never overwrite them.
- When upstream changes its own CLAUDE.md, keep ours: git checkout --ours CLAUDE.md
HTML comments are stripped before Claude sees this file, so notes here cost no tokens.
-->

# Optio — air-gapped fork

Optio runs coding agents (Claude Code, OpenCode, …) in Kubernetes pods and drives them from a web UI:
people or events describe **work**, Optio runs an agent CLI in a pod, streams its output, and follows the
merge request until it merges. We run it inside an air-gapped network on Rancher, with internal GitLab,
Jira and a LiteLLM gateway (a small fast model and a contract Claude model).

## Rules — read before doing anything

1. **Know what we are doing.** At the start of a task read the "Now" and "Decisions" sections of
   `docs/airgap/worklog.md`. At the end add one dated line to its "Log" (what changed, where, result).
2. **Know the main ideas.** For any non-trivial task read `docs/agent-guides/README.md` once (Optio's
   concepts in one page). Each folder has an `AGENTS.md` with its own main ideas — it loads when you work there.
3. **No internet.** Never `curl`/`git fetch` public hosts, never `pnpm install` from the public registry,
   never WebSearch/WebFetch. Everything you need is in this repo.
4. **Do not read the root `AGENTS.md` top to bottom** (67 KB). Grep it for one term: `grep -n "GITLAB_HOSTS" AGENTS.md`.
5. **Never open** `apps/android`, `apps/ios`, `apps/site`, `design`, `docs/design`, `docs/audits`,
   `pnpm-lock.yaml`, `node_modules`, `dist`, `.next` (blocked in `.claude/settings.json`).
6. **Wide searches → the `optio-scout` subagent.** Not the built-in Explore/Plan agents: they skip these guides.
7. **Budget:** after 8 files without naming the failing function, STOP and report what you found
   (file:line evidence) and what you would open next.
8. **Done means:** targeted tests pass, `bash scripts/airgap/impact.sh` was run, and you say which images
   or chart must be republished.
9. **Never print secret values** (tokens, `OPTIO_ENCRYPTION_KEY`, `DATABASE_URL`, kube Secrets).
10. **Fork-only code** gets a `// AIRGAP-FORK: <why>` comment so upstream syncs can find it.

## Site facts (registry, release, hosts, kit version)

@docs/airgap/site-facts.md

## Map — where things live

| Path                                                | What it is                                                      | Ships in               |
| --------------------------------------------------- | --------------------------------------------------------------- | ---------------------- |
| `apps/api`                                          | backend: HTTP + every worker in one process                     | `optio-api` image      |
| `apps/web`                                          | UI (Next.js)                                                    | `optio-web` image      |
| `apps/cli`                                          | `optio` CLI + machine daemon                                    | inside `optio-api`     |
| `packages/shared`                                   | types and pure rules (state machine, work spec, outbound guard) | api + web              |
| `packages/ticket-providers`                         | Jira / GitLab / GitHub / Linear / Notion                        | api                    |
| `packages/agent-adapters`                           | how each agent CLI is launched and read                         | api                    |
| `packages/container-runtime`                        | pods, exec, run protocol, fake runtime                          | api                    |
| `packages/mcp-bridge`                               | MCP servers inside agent pods                                   | agent images (+ api)   |
| `images`, `scripts/repo-init.sh`, `scripts/optio-*` | agent pod images and their scripts                              | `optio-agent-*` images |
| `helm/optio`                                        | the chart (+ Rancher form)                                      | `helm upgrade`         |
| `scripts/offline`, `deploy/zarf`                    | offline kit and offline builds                                  | build tooling          |
| `docs/airgap`, `scripts/airgap`                     | this fork: what we do, gotchas, helpers                         | —                      |

File-level map and "change → rebuild" matrix: `MANIFEST.md`.

## Routing — symptom → start here

| Symptom                                             | Open first                                        | Then                                           |
| --------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------- |
| GitLab: clone, token, MR, pipeline, webhook, issues | skill `optio-debug-gitlab`                        | `apps/api/src/services/git-platform/gitlab.ts` |
| Jira: no tickets, 401/404, webhook ignored          | skill `optio-debug-jira`                          | `packages/ticket-providers/src/jira.ts`        |
| `blocked: host resolves to a private address`       | `docs/airgap/gotchas.md` §1                       | `packages/shared/src/utils/outbound-http.ts`   |
| TLS / `unable to get local issuer certificate`      | `docs/airgap/gotchas.md` §2                       | `images/CLAUDE.md`                             |
| Task stuck in queued / provisioning                 | `apps/api/src/workers/task-worker.ts`             | `apps/api/src/services/agent-pod-pool.ts`      |
| Pod up, agent CLI fails / no output                 | `packages/agent-adapters/src/claude-code.ts`      | `apps/api/src/utils/pod-env.ts`                |
| Which Helm value sets env var X (or none does)      | `helm/VALUES-MAP.md` (grep X)                     | `helm/CLAUDE.md`                               |
| Model / LiteLLM / base URL                          | `docs/airgap/gotchas.md` §6                       | `apps/api/src/services/pooled-agent-env.ts`    |
| Webhook arrives, nothing runs                       | `apps/api/src/routes/event-ingress.ts`            | `apps/api/src/services/trigger-dispatch.ts`    |
| Sign-in (OIDC / LDAP / GitLab)                      | `apps/api/src/services/sign-in-config-service.ts` | `docs/sign-in.md`                              |
| UI shows wrong data                                 | `apps/web/src/lib/api-client.ts`                  | the API route it calls                         |
| DB / migration error                                | `apps/api/AGENTS.md` (Change it safely)           | `apps/api/src/db/schema.ts`                    |
| Build, push, deploy a change                        | skill `optio-rebuild-publish`                     | `scripts/offline/build-images.sh`              |
| Debug the running system                            | skill `optio-debug-live`                          | —                                              |
| New upstream version arrived                        | skill `optio-sync-upstream`                       | —                                              |
| Guides out of date                                  | skill `optio-refresh-guides`                      | `scripts/check-agent-guides.sh`                |

## Test — offline, fastest first

- One file: `pnpm --filter @optio/api exec vitest run src/services/git-platform/gitlab.test.ts`
- One package: `pnpm --filter @optio/ticket-providers test` · types: `pnpm --filter @optio/api typecheck`
- Integration (Docker + mirrored postgres/redis images): `pnpm --filter @optio/api test:integration`
- Do NOT run `pnpm check:push`, `scripts/smoke-e2e.sh` or Playwright unless asked.
- Packages: `@optio/api` `@optio/web` `@optio/cli` `@optio/shared` `@optio/ticket-providers` `@optio/agent-adapters` `@optio/container-runtime` `@optio/mcp-bridge`

## Conventions that bite

- ESM: TypeScript imports end in .js (`import { x } from "./y.js"`).
- Run state changes only through `taskService.transitionTask()`.
- New DB migrations: hand-written SQL, unix-timestamp prefix.
- Never reuse an image tag. Commits: conventional (`fix(gitlab): …`).
