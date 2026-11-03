# apps/api/src/services — the logic, grouped by domain

About 240 modules in one flat folder. **All file names below are in `apps/api/src/services/`.**
Find your domain, read its main idea, open only those files. Each x.ts usually has x.test.ts next to it:
read the test to learn the contract. Skip groups unrelated to your task.

## Git platforms — GitHub, GitLab, CodeCommit

Main idea: one interface (`git-platform/index.ts` picks the implementation from the repo's saved platform),
one file per platform for PR/MR, CI, merge and branch calls. Agents never hold long-lived tokens: the pod's
git credential helper asks the API, which answers only for allowed hosts with a scoped short-lived token.

- `git-platform/index.ts`, `git-platform/gitlab.ts` (MRs, pipelines, merge, branches), `git-platform/gitlab-ci-logs.ts`, `git-platform/github.ts`, `git-platform/codecommit.ts`, `git-platform/pr-search.ts`
- Tokens and credentials: `git-token-service.ts` (which token for which host), `git-access-env.ts` (git env of a pod), `git-credential-scope.ts` (signed scope for the in-pod helper)
- `gitlab-commit-identity.ts`, `github-app-service.ts`, `github-token-service.ts`, `github-repo-browse-service.ts`, `codecommit-credential-service.ts`
- Repos: `repo-service.ts`, `repo-detect-service.ts`

## Tickets — Jira, GitLab issues, GitHub issues, Linear, Notion

Main idea: a worker polls each configured provider for labeled, open tickets and turns new ones into work;
the run links back to the ticket (comments, state, commit trailers). Providers live in `packages/ticket-providers`.

- `ticket-sync-service.ts` (poll → create work), `ticket-provider-credentials.ts` (which secret a provider uses), `ticket-context.ts`
- Links between work and tickets: `work-link-status-service.ts`, `work-traceability.ts`, `commit-trailers.ts`

## Triggers and incoming webhooks

Main idea: one trigger table for every target, one dispatcher. Whatever fires — cron, webhook, ticket,
platform event — ends in `fireTrigger`, which starts what the target starts.

- `trigger-service.ts` (CRUD + validation), `trigger-dispatch.ts` (`fireTrigger`)
- `event-trigger-service.ts` (match GitHub/GitLab/Jira/Slack/… events to triggers), `inbound-delivery-service.ts`, `trigger-delivery.ts`
- Outgoing webhooks: `webhook-service.ts`. HMAC for internal calls: `hmac-auth-service.ts`
- The receiving route: `apps/api/src/routes/event-ingress.ts`

## Work, tasks and jobs — what to run

Main idea: every kind of work is written from one spec (When/Where/Who/What/Then) and every run changes
state through `transitionTask` only.

- `work-service.ts` (Work list), `work-write-service.ts` (create/update from a WorkSpec), `work-definition-service.ts`, `work-ownership.ts`
- `task-service.ts` (`transitionTask`), `task-control-service.ts`, `task-cancellation-service.ts`, `task-pr-service.ts`, `task-config-service.ts`, `subtask-service.ts`, `unified-task-service.ts`, `dependency-service.ts`
- Jobs: `workflow-service.ts`, `command-run.ts`, `command-template-check.ts`
- Messages to running agents: `task-message-service.ts`, `task-message-delivery.ts`. Comments: `comment-service.ts`
- Prompts: `prompt-template-service.ts`, `starter-prompts.ts`

## Pods — where agents run

Main idea: every agent pod is a row in `agent_pods`; `pickPod` reuses, balances, then scales out. Repo pods
are StatefulSets with a PVC; Job pods are pooled per Job; persistent agents have warm windows.

- `agent-pod-pool.ts` (`pickPod`), `repo-pool-service.ts`, `workflow-pool-service.ts`, `persistent-agent-pool-service.ts`
- `k8s-workload-service.ts`, `container-service.ts`, `pod-isolation.ts`, `agent-node-placement.ts`, `envoy-sidecar.ts` (secret-injecting proxy sidecar)
- Cleanup and caches: `zombie-cleanup-service.ts`, `run-home-sweep-service.ts`, `shared-directory-service.ts`

## Agent environment, models and sign-in

Main idea: before a run, defaults (workspace, repo) plus the work's own settings become the files and env
the agent sees: MCP servers, skills, connection credentials, model provider, sign-in secret.

- `agent-environment-service.ts` (`buildAgentEnvironment`), `pooled-agent-env.ts`, `pooled-agent-command.ts`, `agent-options-env.ts`, `agent-options-service.ts`, `opencode-run-setup.ts`, `pi-provider-secrets.ts`
- `agent-credential-service.ts` (which sign-in secret a run uses), `model-provider-service.ts` (e.g. Bedrock), `auth-failure-detector.ts`

## Agent output → logs and cost

Main idea: each agent CLI prints its own event format; one parser per CLI turns it into log rows and usage.

- `agent-event-parser.ts`, `event-parsers.ts`, `opencode-event-parser.ts`, `codex-event-parser.ts`, `gemini-event-parser.ts`, `cursor-event-parser.ts`, `copilot-event-parser.ts`, `pi-event-parser.ts`, `openclaw-event-parser.ts`
- `activity-flush.ts` (debounced "last activity" — stall detection reads it)
- `run-log-service.ts` (`task_logs`), `run-usage.ts`, `run-output-digest.ts`, `usage-service.ts`, `usage-budget-service.ts`, `analytics-service.ts`

## PRs / MRs and reviews

Main idea: the agent stops after opening a PR; Optio then watches it, may run a review agent, and resumes
the agent with the facts (failed checks, review comments, conflicts).

- `pr-detection-service.ts`, `pr-conversation.ts`, `pr-review-service.ts`, `pr-review-state.ts`, `review-service.ts`, `review-config.ts`, `auto-merge-guard.ts`, `resume-facts.ts`, `resume-prompts.ts`

## Reconciler — the control loop

Main idea: read a snapshot, decide one action with pure rules (`packages/shared/src/reconcile/`), apply it
with compare-and-swap. Safe to run on several replicas at once.

- `reconcile-snapshot.ts`, `reconcile-executor.ts`, `reconcile-queue.ts`, `claim-lock.ts`, `lease-service.ts`, `poller-lease.ts`
- Several replicas: `run-attachment.ts` (which replica streams a run), `repeat-jobs.ts` (periodic ticks as BullMQ schedulers)

## Connections, MCP servers, skills

Main idea: a connection is an account at a service made of parts (credentials, tools, shell env, a note);
it is assigned to repos or agent types and injected into pods.

- `connection-service.ts`, `connection-catalog-service.ts`, `connection-health.ts`, `mcp-server-service.ts`, `skill-service.ts`, `installed-skill-service.ts`

## Secrets

- `secret-service.ts` (`resolvePodSecrets`: secrets a work picks become env vars of the same name), `credential-secret-service.ts`, `api-key-service.ts`, folder `crypto/`

## Sign-in, users, workspaces, ownership

Main idea: resources belong to the organization or to one person, inside a workspace with roles.

- `sign-in-config-service.ts`, `sign-in-env.ts`, folders `auth/` and `oauth/` (`oauth/gitlab.ts`), `auth-service.ts`, `login-attempt-limit.ts`
- `workspace-service.ts`, `founding-workspace.ts`, `ownership.ts`, `deployment-admin-gates.ts`, `feature-guard.ts`, `deployment-settings.ts`, `optio-settings-service.ts`

## Persistent agents, sessions, controller MCP

- `persistent-agent-service.ts`, `controller-service.ts`, `controller-mcp.ts`, `controller-auth.ts` (+ other `controller-*.ts`), `optio-action-service.ts`
- `session-service.ts`, `interactive-session-service.ts`, `session-harness-service.ts`, `session-bus.ts` (+ other `session-*.ts`), `legacy-session-chat-service.ts`

## Plumbing

- `redis-config.ts` (every Redis client), `event-bus.ts`, `event-visibility.ts`, `instance.ts`, `tls-observability.ts`, `version-service.ts`, folder `config/` (config as code)
- Notifications: `notification-service.ts`, `slack-service.ts`. After a DB restore: `database-restore-check.ts`

## Usually not needed for server-side work

- Optio Local machine daemon side: `local-*.ts`
- Mobile push and widgets: `apns-*.ts`, `fcm-*.ts`, `push-fanout.ts`, `glance-service.ts`, `glance-state-service.ts`, `watch-coalescer.ts`
- Remote workspaces (Coder, Codespaces, E2B, Daytona): `remote-workspace-service.ts`, `remote-workspace-policy.ts`, folder `remote-workspaces/`
