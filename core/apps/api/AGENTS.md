# apps/api — the backend (`@optio/api`)

## What it is

The control plane. One Node process (Fastify 5, Drizzle on Postgres, BullMQ on Redis) serves the HTTP API
and WebSockets **and** runs every background worker. It runs from TypeScript source with `tsx`.
Any number of replicas may run against the same Postgres and Redis.

## Main ideas

- **Routes are thin, services hold the logic.** A route validates (Zod schemas in `src/schemas/`), checks
  the role, and calls a service. Find behavior in `src/services/`, not in `src/routes/`.
- **State changes go through one door.** Run state changes only via `taskService.transitionTask()`
  (validates against the shared state machine, writes, records an event, publishes to WebSockets).
- **Workers poll or consume queues; the reconciler decides.** Workers start runs, watch PRs, sync tickets,
  fire schedules. Anything that asks "what should happen to this run now?" is the reconciler's job
  (`src/workers/reconcile-worker.ts`, pure rules in `packages/shared/src/reconcile/`).
- **Postgres is the source of truth; Redis is transport.** Leases and claims in Postgres make several API
  replicas safe. Redis carries queues and live log frames.
- **One table for every run.** `tasks` holds Repo Task runs and Job runs (`kind`); views `repo_tasks` and
  `workflow_runs` give each kind its old column names. Logs of every run kind go to `task_logs`.
- **Secrets never leave encrypted.** AES-256-GCM at rest; routes never return values; logs never print them.

## How a Repo Task flows through this app

1. `POST /api/work` → `src/routes/work.ts` → `src/services/work-write-service.ts` writes the row (+ trigger).
2. Queued → `src/workers/task-worker.ts` claims it within concurrency limits.
3. Pod: `src/services/agent-pod-pool.ts` (`pickPod`) → `src/services/repo-pool-service.ts` (StatefulSet + PVC).
4. Environment: `src/services/agent-environment-service.ts` builds MCP config, skills, env; `src/utils/pod-env.ts` writes it.
5. Run: started through `packages/container-runtime` using the adapter from `packages/agent-adapters`.
6. Output → parsers (`src/services/*-event-parser.ts`) → `task_logs`, cost on the run row.
7. PR/MR URL seen → `pr_opened` → `src/workers/pr-watcher-worker.ts` → reconciler → resume / complete / fail.

## Where things are

| Path                                      | What                                                                   |
| ----------------------------------------- | ---------------------------------------------------------------------- |
| `apps/api/src/index.ts`                   | boot: migrations, then starts every worker                             |
| `apps/api/src/server.ts`                  | builds the Fastify app and registers every route file                  |
| `apps/api/src/plugins/auth.ts`            | sessions, personal access tokens, roles, default-deny for viewers      |
| `apps/api/src/routes/`                    | one file per HTTP area                                                 |
| `apps/api/src/services/`                  | the logic — index in `apps/api/src/services/AGENTS.md`                 |
| `apps/api/src/workers/`                   | background workers (table below)                                       |
| `apps/api/src/ws/`                        | WebSockets: log streams, session chat and terminal, events             |
| `apps/api/src/schemas/`                   | Zod request bodies                                                     |
| `apps/api/src/db/schema.ts`               | the whole Drizzle schema; `apps/api/src/db/run-views.ts` the run views |
| `apps/api/src/db/migrations/`             | hand-written SQL migrations, applied at boot                           |
| `apps/api/src/utils/pod-env.ts`           | env and setup files every agent pod gets                               |
| `apps/api/src/utils/webhook-signature.ts` | signature checks for incoming webhooks                                 |
| `apps/api/src/test-utils/`                | test doubles (`fake-gitlab.ts`), route test app, e2e server            |
| `apps/api/e2e/`                           | pipeline e2e tests: real server, fake pods                             |

## Workers

| File in `apps/api/src/workers/`                       | Does                                                |
| ----------------------------------------------------- | --------------------------------------------------- |
| `task-worker.ts`                                      | runs Repo Tasks in repo pods                        |
| `workflow-worker.ts`                                  | runs Jobs in pooled pods                            |
| `persistent-agent-worker.ts`                          | runs persistent-agent turns                         |
| `workflow-trigger-worker.ts`                          | fires cron schedules                                |
| `ticket-sync-worker.ts`                               | polls ticket providers                              |
| `pr-watcher-worker.ts`                                | polls PR/MR state, CI and reviews                   |
| `pr-review-worker.ts`, `external-pr-review-worker.ts` | review agents                                       |
| `reconcile-worker.ts`                                 | the control loop (`docs/reconciliation.md`)         |
| `repo-cleanup-worker.ts`                              | idle pod cleanup, dead pod detection                |
| `webhook-worker.ts`                                   | outgoing webhook deliveries                         |
| `trigger-delivery-worker.ts`                          | durable delivery of incoming trigger events         |
| `token-validation-worker.ts`                          | checks the stored agent sign-in still works         |
| `config-sync-worker.ts`                               | applies the config-as-code directory                |
| `sweep-worker.ts`, `attach-sweep-worker.ts`           | housekeeping; hands orphaned runs to a live replica |

## Change it safely

- Schema change: edit `apps/api/src/db/schema.ts` AND add a SQL file in `apps/api/src/db/migrations/` with a
  unix-timestamp prefix (copy the newest file's format). Never rename the old `00xx_` files.
  A new run column goes into `runColumns()` too — read `apps/api/src/db/run-views.ts` first.
- New env var: grep how others are read (`grep -rn "process.env.OPTIO_" apps/api/src | head`) and add it to
  `helm/optio/templates/secrets.yaml` if the chart should set it.
- Tests next to code. One file: `pnpm --filter @optio/api exec vitest run src/services/task-service.test.ts`.
  Integration (`*.int.test.ts`, needs Docker): `pnpm --filter @optio/api test:integration`.
  Pipeline e2e (`e2e/*.e2e.test.ts`): `pnpm --filter @optio/api test:e2e` — script the fake agent with
  prompt directives such as `[[mock:pr]]` and `[[mock:fail]]` (`packages/container-runtime/src/fake.ts`).
- Types: `pnpm --filter @optio/api typecheck`.
