# packages/shared — types and pure rules (`@optio/shared`)

## What it is

The code the API, the web UI and the CLI must agree on. Mostly types and pure functions with no I/O,
so the same rule runs in the browser and on the server. Exported straight from `src/index.ts`
(plus subpaths such as `@optio/shared/outbound-http`). Ships in the `optio-api` and `optio-web` images.

## Main ideas

- **One rule, many callers.** If the form and the server must decide the same thing (which kind a piece of
  work is, which state transitions are legal, what an error means), the rule lives here.
- **Work spec.** `src/work/spec.ts`: the five attributes and `deriveWorkKind` / `kindOfSpec`.
  `src/work/settings.ts`: per-work settings layered over the repo's (a work may be stricter, never looser).
- **State machine.** `src/utils/state-machine.ts`: legal run transitions; illegal ones throw.
- **Reconciler rules.** `src/reconcile/`: pure functions from a snapshot to one action, one file per run kind.
- **Outbound guard.** `src/utils/outbound-http.ts` (`guardedFetch`) + `src/utils/ssrf.ts`: every URL a person
  typed is vetted (scheme, DNS answers, private ranges, deployment allow-list) and pinned before the API calls it.
- **Error classifier.** `src/error-classifier.ts`: maps raw errors to a category and a remedy shown in the UI.
- **Types feed the mobile apps.** `src/types/` is generated into Swift and Kotlin (`pnpm gen:swift`, `pnpm gen:kotlin`).

## Where things are

| Path                                                                              | What                                                                                  |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `packages/shared/src/types/`                                                      | API types: `task.ts`, `ticket.ts`, `triggers.ts`, `git-platform.ts`, `workflow.ts`, … |
| `packages/shared/src/work/`                                                       | work spec, settings, feed                                                             |
| `packages/shared/src/reconcile/`                                                  | reconciler decisions per run kind                                                     |
| `packages/shared/src/utils/state-machine.ts`                                      | run state transitions                                                                 |
| `packages/shared/src/utils/parse-repo-url.ts`                                     | repo URL → platform, host, owner, name                                                |
| `packages/shared/src/utils/outbound-http.ts`, `packages/shared/src/utils/ssrf.ts` | outbound HTTP guard                                                                   |
| `packages/shared/src/prompt-template.ts`                                          | `{{param}}` and `{{#if}}` rendering                                                   |
| `packages/shared/src/prompt-template-gitlab.ts`                                   | GitLab wording for prompts                                                            |
| `packages/shared/src/error-classifier.ts`                                         | error → category + remedy                                                             |
| `packages/shared/src/constants.ts`                                                | defaults (ticket label, limits, …)                                                    |
| `packages/shared/src/config/`                                                     | config-as-code manifest types, feature lists                                          |

## Change it safely

- A change here rebuilds both `optio-api` and `optio-web`.
- Tests: `pnpm --filter @optio/shared test`. Types: `pnpm --filter @optio/shared typecheck`.
- Changing `src/types/` makes upstream CI require regenerated Swift/Kotlin models (`pnpm gen:swift`, `pnpm gen:kotlin`).
