# packages/ticket-providers — issue trackers (`@optio/ticket-providers`)

## What it is

One class per tracker that Optio can read work from: Jira, GitLab issues, GitHub issues, Linear, Notion.
Used by the API's ticket sync worker. Ships in the `optio-api` image.

## Main ideas

- **One interface, `TicketProvider`** (`packages/ticket-providers/src/types.ts`): fetch actionable tickets
  (labeled `optio` by default and not done), read and add comments, read or update state.
  `getTicketProvider(source)` in `packages/ticket-providers/src/index.ts` picks the class.
- **Providers are stateless.** Config (base URL, project, label, token) is passed on every call; the API
  decides which secret a provider gets (`apps/api/src/services/ticket-provider-credentials.ts`).
- **All HTTP goes through the outbound guard** (`guardedFetch` from `@optio/shared/outbound-http`):
  private hosts must be allowed by the deployment, and redirects are not followed blindly.
- **Jira today means Jira Cloud.** `jira.ts` uses `jira.js` `Version3Client` (REST API v3, the
  `/rest/api/3/search/jql` endpoint), Basic auth with email + API token, and reads Atlassian Document Format.
  Jira Server / Data Center (REST v2, Bearer personal access token, plain-text bodies) is not covered.

## Where things are

| Path                                                                                                                            | What                                                 |
| ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `packages/ticket-providers/src/types.ts`                                                                                        | the `TicketProvider` interface                       |
| `packages/ticket-providers/src/index.ts`                                                                                        | `getTicketProvider`                                  |
| `packages/ticket-providers/src/jira.ts`                                                                                         | Jira Cloud                                           |
| `packages/ticket-providers/src/gitlab.ts`                                                                                       | GitLab issues (project or group, self-managed hosts) |
| `packages/ticket-providers/src/github.ts`, `packages/ticket-providers/src/linear.ts`, `packages/ticket-providers/src/notion.ts` | the others                                           |
| `packages/shared/src/types/ticket.ts`                                                                                           | `Ticket`, `TicketComment`, `TicketSource`            |

## Change it safely

- Add a variant behind a config flag and keep the existing path working; copy the test style of
  `packages/ticket-providers/src/jira.test.ts` (it stubs HTTP; `jira-ssrf.test.ts` covers the guard).
- Tests: `pnpm --filter @optio/ticket-providers test`. Types: `pnpm --filter @optio/ticket-providers typecheck`.
- Polling and work creation are in `apps/api/src/services/ticket-sync-service.ts`; the setup form in
  `apps/web/src/components/setup/ticket-sources.ts`.
