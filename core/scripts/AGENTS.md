# scripts

## What it is

Three different kinds of script live here. Know which kind you are touching.

## Main ideas

1. **Baked into agent images** — they run inside agent pods, so a change means rebuilding agent images:
   `scripts/repo-init.sh` (pod entrypoint: configure git, clone, sleep), `scripts/optio-git-credential`
   (git credential helper: asks the API for a token for the asking host, HMAC-signed),
   `scripts/optio-gh-wrapper`, `scripts/optio-glab-wrapper`, `scripts/check-preinstalled-mcp.mjs`.
2. **Offline kit and offline builds** (`scripts/offline/`) — for installations without internet:
   `make-kit.sh` (on a connected host: base images, pnpm store, tools), `load-kit.sh` (push the kit to a
   registry), `build-images.sh` (build api, web and agent images with no network), `check-offline-build.sh`,
   `kit-scan.sh`. Each script documents its flags in its header comment. Guide: `docs/air-gapped.md`.
3. **Developer and CI helpers** — `setup-local.sh` / `update-local.sh` (Docker Desktop Kubernetes),
   `test-infra.sh` (test Postgres/Redis containers), `check-push.mjs` (CI locally), `smoke-e2e.sh`
   (live cluster + one real LLM run), `check-migration-prefixes.sh`, `changed-surfaces.mjs`.

## Where things are

| Path                              | What                                                                       |
| --------------------------------- | -------------------------------------------------------------------------- |
| `scripts/offline/build-images.sh` | `<version> [--offline] [--only names] [--presets] [--push] [--registry r]` |
| `scripts/offline/presets.txt`     | which `optio-agent-<preset>` images exist                                  |
| `scripts/backup/`                 | database backup and restore (`docs/backup.md`)                             |
| `scripts/check-agent-guides.sh`   | checks that paths named in the agent guides exist; value map is current    |
| `scripts/helm-value-map.sh`       | regenerates `helm/VALUES-MAP.md` from the chart and the code               |

## Change it safely

- Read a script's header before running it: `head -50 scripts/offline/build-images.sh`.
- Scripts in group 1 run as the agent user in the pod; keep them POSIX-friendly and quiet about secrets.
