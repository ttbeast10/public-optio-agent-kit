# Optio for coding agents — the main ideas and the guide index

Read this once before a non-trivial task. Each area has its own short `AGENTS.md` (index at the end);
the root `AGENTS.md` is the long reference — grep it, don't read it whole.

## 1. What Optio is

"CI/CD where the build step is an AI agent." People (or events) describe **work**; Optio runs an agent
CLI (Claude Code, OpenCode, Codex, Gemini, Copilot, Cursor, Pi, OpenClaw) in a Kubernetes pod, streams its
output to the UI, and — for repo work — follows the pull/merge request until it merges.

## 2. Everything is "work" with five attributes

| Attribute | Question       | Examples                                                                         |
| --------- | -------------- | -------------------------------------------------------------------------------- |
| When      | what starts it | now, cron schedule, webhook, ticket, GitHub/GitLab/Jira/Slack/… event            |
| Where     | where it runs  | a repo pod (with a checkout) or a pod without a repo; or the user's own machine  |
| Who       | which runtime  | an agent CLI + options (model, effort), or a plain shell command                 |
| What      | the prompt     | text or a saved prompt template with `{{params}}`                                |
| Then      | when it ends   | exits when done / waits for me (session) / waits for messages (persistent agent) |

The answers decide the **kind** (`deriveWorkKind` in `packages/shared/src/work/spec.ts`):

- **Repo Task** — has a repo, exits when done → clones, works in a git worktree, opens a PR/MR.
- **Job** (standalone) — no repo → runs in a pooled pod, produces logs and side effects.
- **Persistent agent** — waits for messages → long-lived, wakes on messages, cron, webhooks, tickets.
- **Scheduled Task / Job / Local automation** — the same, saved as a definition that a trigger re-runs.
- **Session** — waits for you → an interactive pod terminal + agent chat.

Storage names are older than the UI names: `tasks` holds every run (`kind` = `repo` | `standalone`),
`work_definitions` holds every re-runnable definition, `workflow_triggers` holds every trigger.

## 3. Where agents run: pods, worktrees and the run protocol

- **Pod per repo, worktree per task.** A repo pod clones once and sleeps; each task `git worktree add`s,
  runs the agent, cleans up. Several tasks share a pod; pods scale out per repo and are reaped when idle.
- Every agent pod (repo, Job, persistent agent) is one row in `agent_pods`, chosen by `pickPod`:
  same pod as last time → least loaded → scale out.
- **Run protocol.** An agent is started detached inside the pod (a supervisor, files in a run directory).
  The API only runs short `exec`s: start, attach (tail the output), deliver (stdin), kill. So any API replica
  can pick up a run after a restart. A **fake runtime** plays the same protocol for tests.

## 4. The life of a Repo Task

`pending → queued → provisioning → running → pr_opened → completed`, with `needs_attention`, `failed`
(retry → `queued`) and `cancelled` on the side. Rules live in `packages/shared/src/utils/state-machine.ts`;
every change goes through `taskService.transitionTask()`.

1. The task worker takes it from the queue (concurrency limits: global and per repo).
2. A pod is picked, the agent runs in a worktree, output is parsed into logs and cost.
3. The agent pushes a branch and opens a PR/MR, then stops (it does not wait for CI).
4. The PR watcher polls CI, reviews and merge state; an optional review agent runs.
5. The **reconciler** decides what happens next: resume the agent on failed CI / review comments / conflicts,
   complete on merge, fail on close, detect stalls and dead pods.

## 5. The control plane

- One API process type: HTTP routes **and** every background worker. Any number of replicas.
- **Postgres is the truth** (runs, logs, definitions, secrets — encrypted). **Redis** carries BullMQ queues
  and pub/sub for live logs. Replicas coordinate with leases and claims in Postgres.
- **Reconciler pattern:** pure decision functions read a frozen snapshot of the world and return one action;
  an executor applies it with compare-and-swap. Producers just "wake" the reconciler.

## 6. Integrations

- **Git platforms:** GitHub, GitLab (incl. self-managed), CodeCommit — one interface, one file each.
  Agents get git credentials from a helper in the pod that asks the API for a short-lived, scoped token.
- **Tickets:** Jira, GitLab issues, GitHub issues, Linear, Notion — a labeled ticket becomes work.
- **Triggers:** one table, one dispatcher (`fireTrigger`). Event sources post signed webhooks to the API.
- **Connections:** a named account at a service = credentials + MCP tools + shell env + a skill note.
  They are injected into each agent pod (`.mcp.json` for Claude Code, each harness's own config for the rest).
- **Controller MCP:** agents (and outside clients) can create work and message other agents through MCP.

## 7. Who owns what

Every resource is the **organization's** or one person's **private** one, inside a **workspace**
(roles admin / member / viewer). Private work runs only with its owner's secrets and connections.

## 8. Shipping

Images: `optio-api` (API + CLI tarball), `optio-web`, `optio-agent-base` + language presets (+ dind).
Deploy with the Helm chart in `helm/optio` (value → env var → code: `helm/VALUES-MAP.md`). Offline builds and an offline kit: `docs/air-gapped.md`.

## 9. Guide index

| Area                 | Guide                                  | Main idea in one line                                     |
| -------------------- | -------------------------------------- | --------------------------------------------------------- |
| Backend              | `apps/api/AGENTS.md`                   | HTTP + workers in one process; services hold the logic    |
| Backend services     | `apps/api/src/services/AGENTS.md`      | about 240 service modules grouped by domain               |
| Web UI               | `apps/web/AGENTS.md`                   | Next.js pages that call the API through one client        |
| CLI + machine daemon | `apps/cli/AGENTS.md`                   | terminal client; `optio local up` runs agents on a laptop |
| Shared library       | `packages/shared/AGENTS.md`            | types and pure rules shared by API, web and CLI           |
| Ticket sources       | `packages/ticket-providers/AGENTS.md`  | one `TicketProvider` per tracker                          |
| Agent adapters       | `packages/agent-adapters/AGENTS.md`    | how each agent CLI is launched and its output read        |
| Container runtime    | `packages/container-runtime/AGENTS.md` | pods, exec and the run protocol                           |
| MCP bridges          | `packages/mcp-bridge/AGENTS.md`        | stdio MCP servers baked into agent images                 |
| Helm chart           | `helm/AGENTS.md`                       | how values become env, Secrets and pods; value map        |
| Agent images         | `images/AGENTS.md`                     | what an agent pod contains                                |
| Scripts              | `scripts/AGENTS.md`                    | in-pod scripts, offline kit, dev and CI helpers           |

Long-form docs: `docs/tasks.md`, `docs/reconciliation.md`, `docs/connections.md`, `docs/scope.md`,
`docs/config-as-code.md`, `docs/persistent-agents.md`, `docs/controller-mcp.md`, `docs/air-gapped.md`.

## 10. Keeping these guides true

`bash scripts/check-agent-guides.sh` fails when a guide names a file that no longer exists or when the
generated `helm/VALUES-MAP.md` is out of date (`bash scripts/helm-value-map.sh` refreshes it), and lists
service modules the services guide does not mention yet. Run it after moving files or changing the chart.
