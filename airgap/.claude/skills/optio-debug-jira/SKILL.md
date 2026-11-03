---
name: optio-debug-jira
description: Triage Optio's Jira integration — tickets not synced, 401/403/404 from Jira, Jira webhooks ignored, comments or transitions failing — and plan the Jira Server/Data Center patch. Use before opening Jira-related code.
---

# Debug Jira in Optio (air-gapped)

First read `docs/airgap/worklog.md` and the Jira flavor in `docs/airgap/site-facts.md`.

## Fact to know first

Upstream `packages/ticket-providers/src/jira.ts` targets **Jira Cloud only**:

- client `Version3Client` from `jira.js` → REST API **v3** (`/rest/api/3/...`)
- search: `issueSearch.searchForIssuesUsingJqlEnhancedSearch` → `/rest/api/3/search/jql` with `nextPageToken` (Cloud-only endpoint)
- auth: `basic: { email, apiToken }` (Atlassian Cloud API token)
- descriptions/comments: Atlassian Document Format (`adfToPlaintext`)

Jira **Server / Data Center** has only REST **v2**, uses a Personal Access Token as `Authorization: Bearer <PAT>`,
paginates `/rest/api/2/search` with `startAt`/`total`, and uses plain-text/wiki strings, not ADF.
→ If your Jira is Server/DC, the symptom is almost always 404 on search or 401 on auth. Go to "Patch plan".

## Step 1 — Config checks (Cloud or DC)

1. Base URL is the final URL: https, with context path if any (`https://jira.corp/jira`). The client refuses redirects.
2. Outbound policy allows the Jira host: `OPTIO_OUTBOUND_ALLOWED_HOSTS` / `OPTIO_OUTBOUND_ALLOW_PRIVATE` (`docs/airgap/gotchas.md` §1).
3. API pod trusts the Jira CA (`NODE_EXTRA_CA_CERTS`, gotchas §2).
4. Issues carry the trigger label (default label: `DEFAULT_TICKET_LABEL` in `packages/shared/src/constants.ts`) and are not Done/Closed.
5. Webhooks: `webhook.jiraSecret` set and Jira sends `X-Hub-Signature`. Older Jira DC versions may not sign webhooks at all → check `apps/api/src/utils/webhook-signature.ts` and the ingress `apps/api/src/routes/event-ingress.ts`.
6. Logs: `kubectl -n <ns> logs deploy/<release>-api -c api --since=30m | grep -i jira | tail -50`

## Step 2 — Files (open only these)

| What                                | File                                                                                            |
| ----------------------------------- | ----------------------------------------------------------------------------------------------- |
| Provider (all Jira HTTP)            | `packages/ticket-providers/src/jira.ts`                                                         |
| Its tests                           | `packages/ticket-providers/src/jira.test.ts`, `packages/ticket-providers/src/jira-ssrf.test.ts` |
| Provider interface                  | `packages/ticket-providers/src/types.ts`                                                        |
| Polling + creating work             | `apps/api/src/services/ticket-sync-service.ts`, `apps/api/src/workers/ticket-sync-worker.ts`    |
| Which secret/config a provider gets | `apps/api/src/services/ticket-provider-credentials.ts`                                          |
| Ticket types                        | `packages/shared/src/types/ticket.ts`                                                           |
| Setup UI fields                     | `apps/web/src/components/setup/ticket-sources.ts`                                               |

## Patch plan — Jira Server/DC (fork patch, keep Cloud working)

1. Add `flavor?: "cloud" | "datacenter"` (default `"cloud"`) to `JiraProviderConfig`; for DC accept `apiToken` as a PAT and make `email` optional.
2. One factory `makeClient(config)`: Cloud → `Version3Client` + basic; DC → `Version2Client` + Bearer PAT (check what the installed `jira.js` version supports: `ls node_modules/.pnpm | grep jira.js`, then read its `Config` type). Keep `baseRequestConfig: { adapter: guardedJiraAdapter }` for both.
3. Search: DC → `issueSearch.searchForIssuesUsingJql` (v2) with `startAt` loop until `startAt >= total` or `maxPages`.
4. Bodies: DC description/comment is a string → skip `adfToPlaintext`; `addComment` sends `{ body: "<text>" }`.
5. Transitions and `getIssue` work the same on v2.
6. Mark every changed block `// AIRGAP-FORK: Jira DC support`.
7. Tests: copy the style of `jira.test.ts`; add DC cases (Bearer header, v2 paths, startAt paging, string bodies).
   Run `pnpm --filter @optio/ticket-providers test` and `pnpm --filter @optio/ticket-providers typecheck`.
8. UI: add the flavor choice in `apps/web/src/components/setup/ticket-sources.ts` (or set it through the API until then).
9. Rebuild: `api` (+ `web` if UI changed). Consider upstreaming (Asaf already sends PRs).

## Report format

```
Jira flavor: Cloud | Server/DC <version>
Root cause: <one sentence>
Evidence: <file:line>, <log line without secrets>
Fix: <config | patch files>
Test: <command> → pass
Republish: <bash scripts/airgap/impact.sh output>
```

Record the finding in `docs/airgap/worklog.md`.
