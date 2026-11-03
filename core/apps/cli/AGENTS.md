# apps/cli — the `optio` command and the machine daemon (`@optio/cli`)

## What it is

A terminal client for the API (login with a personal access token, create and follow work, manage repos,
secrets, sessions, apply config-as-code manifests) plus **Optio Local**: `optio local up` turns a laptop
into a place where work can run.

## Main ideas

- **Same API as the web UI.** Commands are thin wrappers over HTTP calls (`apps/cli/src/api/`).
- **Optio Local inverts the direction.** The daemon opens one outbound WebSocket to the API, advertises the
  folders it allows, and runs agents and shells in local PTYs. Local agents use the machine's own CLI sign-in;
  no server secrets are sent to laptops.
- **Attention detection** (is the agent waiting for me?) is layered: agent hooks → terminal bell → silence.
- **Config as code:** `optio apply -f` posts manifests; `optio export -o DIR` writes them.
- The CLI is built into a tarball and served by the API image (`/api/cli/optio-cli.tgz`), so a change here
  ships in the `optio-api` image.

## Where things are

| Path                                                                   | What                                                                                            |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `apps/cli/src/program.ts`                                              | command tree                                                                                    |
| `apps/cli/src/commands/`                                               | one folder/file per command group (`task`, `repo`, `session`, `secret`, `local`, `apply.ts`, …) |
| `apps/cli/src/api/`                                                    | HTTP client                                                                                     |
| `apps/cli/src/local/daemon.ts`                                         | Optio Local daemon                                                                              |
| `apps/cli/src/local/agent-command.ts`                                  | how a local agent is launched (permission mode, effort)                                         |
| `apps/cli/src/local/terminal-manager.ts`                               | local PTYs                                                                                      |
| `apps/cli/src/local/attention.ts`, `apps/cli/src/local/hook-server.ts` | "needs you" detection                                                                           |
| `apps/cli/README.md`                                                   | user-facing usage                                                                               |

## Change it safely

- Tests: `pnpm --filter @optio/cli test`. Types: `pnpm --filter @optio/cli typecheck`.
- Server side of Optio Local: `apps/api/src/services/local-*.ts`, `apps/api/src/ws/local-daemon.ts`, `docs/optio-local.md`.
