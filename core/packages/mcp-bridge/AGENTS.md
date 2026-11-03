# packages/mcp-bridge — MCP servers inside agent pods (`@optio/mcp-bridge`)

## What it is

Two small stdio MCP servers, bundled with tsup and baked into the agent images under `/opt/optio/`.
They give any agent CLI tools without installing anything at run time.

## Main ideas

- **REST bridge** (`packages/mcp-bridge/src/bridge.ts`, `packages/mcp-bridge/src/server.ts`): exposes an HTTP API
  as MCP tools. Configured only by env (`OPTIO_HTTP_BASE_URL`, `OPTIO_HTTP_NAME`, …) from a connection, so
  "any REST API" connections (PagerDuty, Pylon, custom HTTP) need no extra image.
- **Controller adapter** (`packages/mcp-bridge/src/controller.ts`): a stdio front for the API's
  Streamable-HTTP controller MCP (`/api/mcp`): create and inspect work, message other agents.
  The API owns the tools and the authorization; the adapter only forwards.
- Pure logic is separated from stdio and network so it is unit-testable.

## Where things are

| Path                                                                                   | What                                      |
| -------------------------------------------------------------------------------------- | ----------------------------------------- |
| `packages/mcp-bridge/src/bridge.ts`                                                    | env contract → tool calls → HTTP requests |
| `packages/mcp-bridge/src/server.ts`, `packages/mcp-bridge/src/index.ts`                | REST bridge stdio server                  |
| `packages/mcp-bridge/src/controller.ts`, `packages/mcp-bridge/src/controller-index.ts` | controller adapter                        |

## Change it safely

- A change here rebuilds **all agent images** (and the API image, which copies every package).
- Tests: `pnpm --filter @optio/mcp-bridge test`. Server side: `apps/api/src/services/controller-mcp.ts`, `docs/controller-mcp.md`.
