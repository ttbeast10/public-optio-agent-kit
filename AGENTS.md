# optio-agent-kit — instructions for agents working on this repo

This repo is the source of the agent guides that get installed into an Optio checkout. It contains no
Optio code. Read `README.md` for the layers and the three publish modes.

## Rules

- Edit guide content in `core/` (generic, must stay upstream-able: no site facts, no air-gap specifics, no
  `AIRGAP-FORK`) or `airgap/` (our fork). A path in `airgap/` overrides the same path in `core/`.
- Paths inside `core/` and `airgap/` mirror the Optio repo. Every path a guide names must exist in Optio:
  test with `tests/run-tests.sh /path/to/optio` (it runs `scripts/check-agent-guides.sh` on an install).
- Keep each `AGENTS.md` under ~120 lines and the root router under ~120 lines. Short beats complete.
- Structure of an area `AGENTS.md`: What it is → Main ideas → (How it flows) → Where things are → Change it safely.
- Never put secret values, hostnames or registry names in any file. Team values belong in the Optio
  checkout's `docs/airgap/site-facts.md`, which the kit only creates when missing.
- Scripts are bash + git + coreutils only (no node, no network). `bash -n` them after editing.
- Markdown is Prettier-formatted (print width 100), because Optio's pre-commit hook checks it.
- After a change: bump `VERSION`, add a `CHANGELOG.md` entry, commit with a conventional message.
