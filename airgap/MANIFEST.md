# MANIFEST — what belongs where (air-gapped fork)

Read on demand. Root `CLAUDE.md` is the short version; `docs/agent-guides/README.md` explains the main ideas.

## 1. Agent guide files and when an agent sees them

Two layers from optio-agent-kit: **core** (generic, could go upstream) and **airgap** (this fork).

| File                                    | Layer                 | Loaded                            | Purpose                                                                       |
| --------------------------------------- | --------------------- | --------------------------------- | ----------------------------------------------------------------------------- |
| `CLAUDE.md`                             | airgap                | every session                     | rules, map, symptom routing (replaces upstream's `@AGENTS.md`)                |
| `docs/airgap/site-facts.md`             | team-owned            | every session (imported)          | our registry, release, hosts, kit version                                     |
| `docs/airgap/worklog.md`                | team-owned            | start/end of each task            | what we are doing now, decisions, log                                         |
| `docs/airgap/README.md`                 | airgap                | on demand                         | why the fork exists, how we work                                              |
| `docs/airgap/gotchas.md`                | airgap                | on demand                         | upstream gaps in an air gap and their fixes                                   |
| `docs/agent-guides/README.md`           | core                  | once per non-trivial task         | Optio's main ideas + index of area guides                                     |
| `<area>/AGENTS.md` + `<area>/CLAUDE.md` | core (+ airgap notes) | when a file in the folder is read | the area's main ideas, file map, how to change it safely                      |
| `.claude/settings.json`                 | airgap                | every session                     | blocks noisy folders and web tools                                            |
| `.claude/settings.local.example.json`   | airgap                | copy it                           | model aliases for LiteLLM (a small fast model, Claude)                        |
| `.claude/agents/optio-scout.md`         | airgap                | when delegated                    | read-only scout → 40-line context pack                                        |
| `.claude/skills/optio-*/SKILL.md`       | airgap                | on demand                         | GitLab, Jira, rebuild-publish, live debug, upstream sync, refresh guides      |
| `scripts/check-agent-guides.sh`         | core                  | run it                            | paths in guides exist; unindexed services                                     |
| `scripts/helm-value-map.sh`             | core                  | run it                            | regenerates `helm/VALUES-MAP.md`                                              |
| `helm/VALUES-MAP.md`                    | generated             | on demand (grep it)               | Helm value → template → env var → code; env the chart never sets; unused keys |
| `.agent-guides`                         | airgap                | read by the check                 | extra guide files to check: `MANIFEST.md`, `docs/airgap`                      |
| `scripts/airgap/impact.sh`              | airgap                | run it                            | changed files → images / Helm / kit / tests                                   |
| `AGENTS.md` (root, upstream)            | upstream              | never by default                  | 67 KB reference. Grep only.                                                   |

Areas with an `AGENTS.md`: `apps/api`, `apps/api/src/services`, `apps/web`, `apps/cli`, `packages/shared`,
`packages/ticket-providers`, `packages/agent-adapters`, `packages/container-runtime`, `packages/mcp-bridge`,
`helm`, `images`, `scripts`. Air-gap notes are appended in the `CLAUDE.md` of `apps/api`, `helm`, `images`,
`packages/ticket-providers`, `scripts`.

## 2. Areas → paths → artifact → tests

| Area                   | Paths                                                                                                                                                  | Artifact                             | Fast tests                                                           |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------ | -------------------------------------------------------------------- |
| HTTP routes            | `apps/api/src/routes/`                                                                                                                                 | api image                            | `pnpm --filter @optio/api exec vitest run src/routes/<file>.test.ts` |
| Business logic         | `apps/api/src/services/`                                                                                                                               | api image                            | same, `src/services/<file>.test.ts`                                  |
| Background workers     | `apps/api/src/workers/`                                                                                                                                | api image                            | same, `src/workers/<file>.test.ts`                                   |
| DB schema + migrations | `apps/api/src/db/`                                                                                                                                     | api image (migrations run at boot)   | `pnpm --filter @optio/api test:integration`                          |
| Request validation     | `apps/api/src/schemas/`                                                                                                                                | api image                            | route tests                                                          |
| WebSockets             | `apps/api/src/ws/`                                                                                                                                     | api image                            | route tests                                                          |
| Auth plugin, roles     | `apps/api/src/plugins/auth.ts`                                                                                                                         | api image                            | `src/plugins/*.test.ts`                                              |
| Pod env builder        | `apps/api/src/utils/pod-env.ts`                                                                                                                        | api image                            | `apps/api/src/utils/pod-env.test.ts`                                 |
| CLI + machine daemon   | `apps/cli/`                                                                                                                                            | api image (CLI tarball inside)       | `pnpm --filter @optio/cli test`                                      |
| UI                     | `apps/web/src/`                                                                                                                                        | web image                            | `pnpm --filter @optio/web test`                                      |
| Shared types/utils     | `packages/shared/src/`                                                                                                                                 | api + web images                     | `pnpm --filter @optio/shared test`                                   |
| Ticket sources         | `packages/ticket-providers/src/`                                                                                                                       | api image                            | `pnpm --filter @optio/ticket-providers test`                         |
| Agent CLI adapters     | `packages/agent-adapters/src/`                                                                                                                         | api image                            | `pnpm --filter @optio/agent-adapters test`                           |
| K8s runtime            | `packages/container-runtime/src/`                                                                                                                      | api image                            | `pnpm --filter @optio/container-runtime test`                        |
| MCP bridges            | `packages/mcp-bridge/src/`                                                                                                                             | agent images (+ api)                 | `pnpm --filter @optio/mcp-bridge test`                               |
| Agent images           | `images/`, `Dockerfile.agent`                                                                                                                          | `optio-agent-base`, `-dind`, presets | build only                                                           |
| In-pod scripts         | `scripts/repo-init.sh`, `scripts/optio-git-credential`, `scripts/optio-gh-wrapper`, `scripts/optio-glab-wrapper`, `scripts/check-preinstalled-mcp.mjs` | agent images                         | build + one live run                                                 |
| Chart                  | `helm/optio/`                                                                                                                                          | Helm release                         | `helm lint helm/optio --set encryption.key=test`                     |
| Zarf package           | `deploy/zarf/`                                                                                                                                         | Zarf tarball                         | `zarf package create`                                                |
| Offline tooling        | `scripts/offline/`                                                                                                                                     | build host only                      | `scripts/offline/*.test.mjs` (node --test)                           |
| Dependencies           | `package.json`, `pnpm-lock.yaml`, `patches/`, `*/package.json`                                                                                         | EVERY image + NEW offline kit        | —                                                                    |
| Not deployed here      | `apps/android`, `apps/ios`, `apps/site`, `design`, `docs/design`, `docs/audits`                                                                        | nothing                              | ignore                                                               |

## 3. Change → what to rebuild (same rules as `scripts/airgap/impact.sh`)

| You changed                                                                                     | Rebuild                                                                                               | Deploy step                                    |
| ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `apps/api/**`, `apps/cli/**`, `packages/{agent-adapters,container-runtime,ticket-providers}/**` | `api`                                                                                                 | helm: `api.image.tag`                          |
| `apps/web/**`                                                                                   | `web`                                                                                                 | helm: `web.image.tag`                          |
| `packages/shared/**`                                                                            | `api`, `web`                                                                                          | both tags                                      |
| `packages/mcp-bridge/**`                                                                        | `api` + all agent images                                                                              | api tag + `agent.image.tag`, recycle repo pods |
| `images/**`, in-pod scripts above, `Dockerfile.agent`                                           | all agent images (`agent-base` first, then `agent-dind` and presets in `scripts/offline/presets.txt`) | `agent.image.tag`, recycle repo pods           |
| `helm/optio/**`                                                                                 | nothing                                                                                               | `helm upgrade` only                            |
| `deploy/zarf/**`                                                                                | Zarf package                                                                                          | `zarf package deploy`                          |
| `package.json`, `pnpm-lock.yaml`, `patches/**`                                                  | new offline kit (made on a connected host, via your approved transfer process) + everything           | full                                           |
| docs, guides, mobile apps, site                                                                 | nothing                                                                                               | —                                              |

`agent.image.tag` is ONE tag for base, dind and every preset: if you bump it, build all of them with that tag.

## 4. Cross-cutting features → files

**GitLab** (full checklist: skill `optio-debug-gitlab`)

- API calls (MRs, pipelines, merge, repo browse): `apps/api/src/services/git-platform/gitlab.ts`, `apps/api/src/services/git-platform/gitlab-ci-logs.ts`, `apps/api/src/services/git-platform/index.ts`
- Host + platform parsing: `packages/shared/src/utils/parse-repo-url.ts`, `packages/shared/src/types/git-platform.ts`
- Tokens + credential helper: `apps/api/src/services/git-token-service.ts`, `apps/api/src/services/git-access-env.ts`, `apps/api/src/services/git-credential-scope.ts`, endpoint `/api/internal/git-credentials` in `apps/api/src/routes/github-app.ts`
- In the pod: `scripts/optio-git-credential`, `scripts/optio-glab-wrapper`, `scripts/repo-init.sh`
- Commit identity: `apps/api/src/services/gitlab-commit-identity.ts`
- Issues as tickets: `packages/ticket-providers/src/gitlab.ts`
- Webhooks: `apps/api/src/routes/event-ingress.ts`, `apps/api/src/utils/webhook-signature.ts`
- Sign-in: `apps/api/src/services/oauth/gitlab.ts`
- UI: `apps/web/src/components/gitlab-repo-browser.tsx`, `apps/web/src/app/repos/new/page.tsx`
- Test double: `apps/api/src/test-utils/fake-gitlab.ts`
- Docs: `docs/gitlab-repositories.md`, `docs/gitlab-tokens.md`

**Jira** (full checklist: skill `optio-debug-jira`)

- Provider: `packages/ticket-providers/src/jira.ts` (tests `jira.test.ts`, `jira-ssrf.test.ts`)
- Sync + credentials: `apps/api/src/services/ticket-sync-service.ts`, `apps/api/src/services/ticket-provider-credentials.ts`, `apps/api/src/workers/ticket-sync-worker.ts`
- Webhooks: `apps/api/src/routes/event-ingress.ts`, `apps/api/src/utils/webhook-signature.ts`
- Types: `packages/shared/src/types/ticket.ts`
- UI: `apps/web/src/components/setup/ticket-sources.ts`, `apps/web/src/app/settings/page.tsx`

**Outbound network + TLS**

- Guard for URLs people type: `packages/shared/src/utils/outbound-http.ts`, `packages/shared/src/utils/ssrf.ts`
- Agent egress policy: `apps/api/src/utils/agent-network-policy.ts`, `helm/optio/templates/network-policy.yaml`
- Notes: `docs/airgap/gotchas.md`

**Models / LLM gateway**

- `apps/api/src/services/pooled-agent-env.ts`, `apps/api/src/services/model-provider-service.ts`, `apps/api/src/services/agent-credential-service.ts`, `docs/model-providers.md`

**Triggers / scheduling**

- `apps/api/src/services/trigger-service.ts`, `apps/api/src/services/trigger-dispatch.ts`, `apps/api/src/services/event-trigger-service.ts`, `apps/api/src/workers/workflow-trigger-worker.ts`, `docs/trigger-delivery.md`

**Run lifecycle**

- `packages/shared/src/utils/state-machine.ts`, `apps/api/src/services/task-service.ts`, `apps/api/src/workers/task-worker.ts`, `apps/api/src/workers/reconcile-worker.ts`, `docs/reconciliation.md`

## 5. Other agent harnesses

Claude Code reads `CLAUDE.md` files (which import each folder's `AGENTS.md`). OpenCode and Codex read
`AGENTS.md` files directly, so they get the same area guides; at the root they still read upstream's 67 KB
`AGENTS.md`, whose "Start here" section points them to `docs/agent-guides/README.md`.
