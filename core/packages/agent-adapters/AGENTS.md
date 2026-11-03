# packages/agent-adapters — one adapter per agent CLI (`@optio/agent-adapters`)

## What it is

The knowledge of how to run each supported agent CLI: Claude Code, OpenCode (interactive and headless),
Codex, Gemini, Copilot, Cursor, Pi, OpenClaw. Ships in the `optio-api` image (the CLIs themselves are
installed in the agent images).

## Main ideas

- **One interface, `AgentAdapter`** (`packages/agent-adapters/src/types.ts`):
  `validateSecrets` (what sign-in it needs), `buildContainerConfig` (command, args, env, files for a run),
  `createResultParser` (read the output line by line as it streams) and `parseResult`.
- **Adapters are pure.** They build a description of the run; the API and the container runtime execute it.
- **Output is read as a stream.** No one holds a whole run's output in memory; a parser is fed line by line
  and `finish(exitCode)` returns the result (summary, PR URL, cost, tokens).
- `getAdapter(type)` in `packages/agent-adapters/src/index.ts` maps an agent type to its adapter.

## Where things are

| Path                                                                                                                                                                                                                                               | What                                                |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `packages/agent-adapters/src/types.ts`                                                                                                                                                                                                             | `AgentAdapter`, `AgentResultParser`                 |
| `packages/agent-adapters/src/index.ts`                                                                                                                                                                                                             | registry (`getAdapter`)                             |
| `packages/agent-adapters/src/claude-code.ts`                                                                                                                                                                                                       | Claude Code                                         |
| `packages/agent-adapters/src/opencode.ts`, `packages/agent-adapters/src/opencode-headless.ts`                                                                                                                                                      | OpenCode (`OPENAI_BASE_URL` from `opencodeBaseUrl`) |
| `packages/agent-adapters/src/codex.ts`, `packages/agent-adapters/src/gemini.ts`, `packages/agent-adapters/src/copilot.ts`, `packages/agent-adapters/src/cursor.ts`, `packages/agent-adapters/src/pi.ts`, `packages/agent-adapters/src/openclaw.ts` | the others                                          |

Related, in the API: env per run `apps/api/src/services/pooled-agent-env.ts`, each CLI's MCP config
`apps/api/src/utils/harness-config.ts`, output parsers `apps/api/src/services/agent-event-parser.ts`.

## Change it safely

- Tests sit next to each adapter (`claude-code.test.ts`, …): `pnpm --filter @optio/agent-adapters test`.
- Upgrading an agent CLI version is an image change (`images/base.Dockerfile` build args), not an adapter change,
  unless its flags or output format changed.
