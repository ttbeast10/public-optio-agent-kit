# packages/container-runtime — pods, exec and the run protocol (`@optio/container-runtime`)

## What it is

The layer between the API and wherever agents run: Kubernetes in production, Docker or local processes
for development, and a fake runtime for tests. Ships in the `optio-api` image.

## Main ideas

- **One interface, `ContainerRuntime`** (`packages/container-runtime/src/types.ts`): create / status / logs /
  exec / destroy a container, plus the four run operations. `createRuntime` picks kubernetes, docker or fake.
- **The run protocol** (`packages/container-runtime/src/run-protocol.ts`): an agent is launched **detached**
  inside the pod by a supervisor, with its files in a run directory (agent.sh, output.ndjson, stdin.ndjson,
  `pid`, `exit`, …). The API uses four short execs:
  - start — run setup, launch the supervisor, print the pid
  - attach — tail `output.ndjson` from a byte offset until the agent exits
  - deliver — append stdin lines for the agent (follow-up messages)
  - kill — signal the run's process group
    Because nothing stays attached, an API restart or a second replica can re-attach to a running agent.
- **The pod's pid 1 must reap** orphaned supervisors (`tini` in the agent image).
- **The fake runtime speaks the same protocol** with local processes and plays an agent that emits Claude
  stream-json. Tests steer it with prompt directives: `[[mock:pr]]`, `[[mock:fail]]`, `[[mock:silent]]`,
  `[[mock:sleep:MS]]`, `[[mock:hang]]`, `[[mock:cost:X]]`. It refuses to start unless `OPTIO_ALLOW_FAKE_RUNTIME=1`.

## Where things are

| Path                                                                                      | What                                  |
| ----------------------------------------------------------------------------------------- | ------------------------------------- |
| `packages/container-runtime/src/types.ts`                                                 | `ContainerRuntime` and run types      |
| `packages/container-runtime/src/index.ts`                                                 | `createRuntime`                       |
| `packages/container-runtime/src/kubernetes.ts`                                            | Kubernetes: pods, exec, logs          |
| `packages/container-runtime/src/run-protocol.ts`                                          | the start/attach/deliver/kill scripts |
| `packages/container-runtime/src/fake.ts`, `packages/container-runtime/src/fake-agent.mjs` | test runtime and fake agent           |
| `packages/container-runtime/src/docker.ts`, `packages/container-runtime/src/process.ts`   | local development runtimes            |

Pod creation (StatefulSets, PVCs, labels) is in the API: `apps/api/src/services/repo-pool-service.ts`.

## Change it safely

- Tests: `pnpm --filter @optio/container-runtime test` (some are Linux-only: `run-protocol.linux.test.ts`).
- A protocol change affects running pods: old pods keep old scripts until they are recycled.
