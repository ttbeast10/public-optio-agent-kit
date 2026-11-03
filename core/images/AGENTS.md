# images — what an agent pod contains

## What it is

Dockerfiles for the images agents run in. The API and web images are built from the root
`Dockerfile.api` and `Dockerfile.web`; this folder is only for agent pods.

## Main ideas

- **Layers:** a toolchain stage (OS packages, git, gh, glab, Node, the agent CLIs, AWS CLI) → `optio-agent-base`
  (adds Optio's own files) → language presets (`node`, `python`, `go`, `rust`, `full`, …) and `dind`, each
  built `FROM` the base through the `BASE_IMAGE` build arg.
- **Optio's own files in every agent image:** `scripts/repo-init.sh` (entrypoint: clone, then sleep),
  `scripts/optio-git-credential` (git asks the API for a scoped token, HMAC-signed),
  `scripts/optio-gh-wrapper` and `scripts/optio-glab-wrapper` (inject tokens for gh/glab),
  `scripts/check-preinstalled-mcp.mjs`, and the MCP bridges from `packages/mcp-bridge` in `/opt/optio/`.
- **`tini` is pid 1** so detached agent supervisors are reaped (see the run protocol).
- **Build args choose the toolchain:** `AGENT_CLIS` (which agent CLIs), `CLAUDE_CODE_VERSION`,
  `OPENCODE_INSTALL_METHOD`, `PREINSTALL_MCP_SERVERS`, mirrored bases (`UBUNTU_IMAGE`, `NODE_SLIM_IMAGE`).
  Full table: `docs/air-gapped.md`.

## Where things are

| Path                                                                                                                             | What                                       |
| -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `images/base.Dockerfile`                                                                                                         | toolchain + `optio-agent-base`             |
| `images/node.Dockerfile`, `images/python.Dockerfile`, `images/go.Dockerfile`, `images/rust.Dockerfile`, `images/full.Dockerfile` | presets                                    |
| `images/dind.Dockerfile`, `images/dind-entrypoint.sh`                                                                            | Docker-in-Docker variant                   |
| `images/build.sh`                                                                                                                | online build of every preset               |
| `scripts/offline/build-images.sh`                                                                                                | offline/registry build (api, web, agent-*) |
| `scripts/offline/presets.txt`                                                                                                    | presets the offline build knows            |

## Change it safely

- Changing any file copied into the base image rebuilds every agent image; Helm uses one tag for all of them.
- Long-lived repo pods keep the image they started with until they are recycled.
