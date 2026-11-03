# apps/web — the UI (`@optio/web`)

## What it is

Next.js 15 App Router, Tailwind CSS v4, Zustand. Ships as the `optio-web` image, which runs as the second
container in the API pod.

## Main ideas

- **The UI owns no business logic.** Every page calls the API through `apps/web/src/lib/api-client.ts`;
  the browser's `/api/*` requests are proxied server-side to the API (`apps/web/src/app/api/[...path]/route.ts`,
  `INTERNAL_API_URL`). Wrong data on screen is usually an API bug.
- **One noun: Work.** The Work list (`/work`) and one creation form (`apps/web/src/components/work-form/`)
  cover every kind. The form derives the kind from the five answers with the same shared rule the server uses.
- **Live updates come over WebSockets** (`apps/web/src/lib/ws-client.ts`): logs, events, terminals.
- **Organization vs private** is fixed UI vocabulary (owner pickers, chips); see `docs/scope.md`.

## Where things are

| Path                                                                  | What                                                                                                        |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `apps/web/src/app/<route>/page.tsx`                                   | one folder per page: `work`, `repos`, `settings`, `setup`, `issues`, `reviews`, `connections`, `secrets`, … |
| `apps/web/src/lib/api-client.ts`                                      | every API call — find the endpoint here first                                                               |
| `apps/web/src/components/work-form/`                                  | the New/Edit work form (`model.ts` decides, `submit.ts` sends)                                              |
| `apps/web/src/components/settings/`, `apps/web/src/components/setup/` | admin screens and the setup wizard                                                                          |
| `apps/web/src/components/gitlab-repo-browser.tsx`                     | GitLab project picker                                                                                       |
| `apps/web/src/components/setup/ticket-sources.ts`                     | ticket provider fields (Jira, GitLab issues, …)                                                             |
| `apps/web/src/components/trigger-selector.tsx`                        | trigger picker                                                                                              |
| `apps/web/src/components/log-viewer.tsx`                              | run logs                                                                                                    |
| `apps/web/src/middleware.ts`                                          | redirects to login when there is no session                                                                 |
| `apps/web/e2e/`                                                       | Playwright specs (need browsers)                                                                            |

## Change it safely

- Zustand: inside callbacks and effects use `useStore.getState()`, not hook selectors (re-render loops).
- Tailwind v4: theme is the `@theme` block in CSS; there is no `tailwind.config` file.
- Imports from workspace packages end in .js (resolved by `extensionAlias` in `apps/web/next.config.ts`).
- One test file: `pnpm --filter @optio/web exec vitest run src/components/gitlab-repo-browser.test.tsx`
- Types: `pnpm --filter @optio/web typecheck`. Build: `pnpm --filter @optio/web build`
  (`OPTIO_OFFLINE_FONTS=1` uses vendored fonts instead of downloading them).
