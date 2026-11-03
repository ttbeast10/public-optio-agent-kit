---
name: optio-debug-gitlab
description: Triage any Optio problem with self-managed GitLab — repo validation, tokens, git clone/push in agent pods, merge requests, pipelines, GitLab issues as tickets, GitLab webhooks, GitLab sign-in. Use before opening GitLab-related code.
---

# Debug GitLab in Optio (air-gapped)

First read `docs/airgap/worklog.md` ("Now", "Open questions") — the issue may already be known.
Main ideas of the code: `apps/api/src/services/AGENTS.md` (Git platforms group).

Work in this order. Stop at the first step that explains the symptom.

## Step 1 — Classify (pick ONE)

| Class                       | Typical symptom                                                                    | Where it runs                |
| --------------------------- | ---------------------------------------------------------------------------------- | ---------------------------- |
| A. API → GitLab REST        | repo won't validate, branches empty, MR status/pipeline never updates, merge fails | API pod                      |
| B. git in the agent pod     | clone/fetch/push fails, `Authentication failed`, TLS error in task log             | agent pod                    |
| C. GitLab → Optio webhook   | push/MR/pipeline event doesn't start work                                          | API pod                      |
| D. GitLab issues as tickets | labeled issues never become tasks                                                  | API pod (ticket sync worker) |
| E. Sign in with GitLab      | redirect to gitlab.com, login loop                                                 | API + web                    |

## Step 2 — Check config before code (most failures are here)

1. `GITLAB_HOSTS` contains the exact `host` or `host:port` → `kubectl -n <ns> exec deploy/<release>-api -c api -- printenv GITLAB_HOSTS`
2. Token secret exists: `GITLAB_TOKEN` or `GITLAB_TOKEN_<HOST>_<PORT>` (names only — never print values). `docs/gitlab-tokens.md`
3. Outbound policy allows the host (A, D): `printenv OPTIO_OUTBOUND_ALLOWED_HOSTS OPTIO_OUTBOUND_ALLOW_PRIVATE`
4. CA trust: API pod has `NODE_EXTRA_CA_CERTS` (A, D, E); agent image has the corporate CA (B). `docs/airgap/gotchas.md` §2
5. Webhook secret equals GitLab's "Secret token" (C): `webhook.gitlabSecret` in Helm values
6. Sign-in base URL (E): `printenv GITLAB_OAUTH_BASE_URL` (the chart can't set it: gotchas §3)
7. Read the API log around the failure: `kubectl -n <ns> logs deploy/<release>-api -c api --since=30m | grep -i gitlab | tail -50`

## Step 3 — Open only the files for your class

| Class               | Files                                                                                                                                                                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A                   | `apps/api/src/services/git-platform/gitlab.ts`, `apps/api/src/services/git-platform/index.ts`, `apps/api/src/services/git-platform/gitlab-ci-logs.ts`, `apps/api/src/services/git-token-service.ts`, `packages/shared/src/utils/parse-repo-url.ts`, `apps/api/src/routes/repos.ts` |
| B                   | `apps/api/src/services/git-access-env.ts`, `apps/api/src/services/git-credential-scope.ts`, `/api/internal/git-credentials` in `apps/api/src/routes/github-app.ts`, `scripts/optio-git-credential`, `scripts/repo-init.sh`, `scripts/optio-glab-wrapper`                           |
| C                   | `apps/api/src/routes/event-ingress.ts`, `apps/api/src/utils/webhook-signature.ts`, `apps/api/src/services/event-trigger-service.ts`, `apps/api/src/services/trigger-dispatch.ts`                                                                                                   |
| D                   | `packages/ticket-providers/src/gitlab.ts`, `apps/api/src/services/ticket-sync-service.ts`, `apps/api/src/services/ticket-provider-credentials.ts`                                                                                                                                  |
| E                   | `apps/api/src/services/oauth/gitlab.ts`, `apps/api/src/services/sign-in-config-service.ts`                                                                                                                                                                                         |
| commit author wrong | `apps/api/src/services/gitlab-commit-identity.ts`                                                                                                                                                                                                                                  |

Each `.ts` has a `.test.ts` next to it: read the test first, it shows the expected requests.

## Step 4 — Reproduce offline

- Test double for the GitLab API: `apps/api/src/test-utils/fake-gitlab.ts`
- Run one file: `pnpm --filter @optio/api exec vitest run src/services/git-platform/gitlab.test.ts`
- Add a failing test that matches your server's behavior (status code, payload, host:port) before fixing.

## Step 5 — Report in this format

```
Class: <A-E>
Root cause: <one sentence>
Evidence: <file:line> and <log line, secrets removed>
Fix: <config change | code change (files)>
Test: <command> → pass
Republish: <output of bash scripts/airgap/impact.sh>
```

Record the finding in `docs/airgap/worklog.md` (Log line; move a solved open question there).
