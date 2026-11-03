# Later: using Claude outside the air gap

> **Status: not in use.** We have no internet-side Claude instance yet; everything in this kit works fully
> inside the air gap. Keep this as the plan for when one exists. Nothing else in the kit depends on it.

For humans. Agents inside the air gap don't need this file.

## The constraint, and the principle that follows

Files move **in** through your approved transfer process. Nothing comes **out** unless your security policy explicitly allows a
reviewed path. So this design is inbound-only: the outside never sees logs, configs or hostnames.

That gives a clean split of ownership:

- **Code** (upstream + our `AIRGAP-FORK` patches + these guides) — source of truth is **outside**, on a
  mirror of the fork branch. It is all public-safe: upstream is public and our patches contain no site data.
- **Site facts, config, secrets, runtime evidence** — source of truth is **inside**
  (`docs/airgap/site-facts.md`, Helm values, the cluster). They never leave.

## Who does what

| Worker                                                              | Strengths                                                                                                         | Use it for                                                                                                     |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Outside Claude** (claude.ai / Claude Code on an internet machine) | strongest models, internet, can read the whole repo and upstream PRs, can run real GitLab CE / Jira DC containers | reproduce integration bugs, write patches + tests, merge upstream, regenerate these guides, build offline kits |
| **Inside, contract Claude**                                         | strong reasoning, sees real config and logs                                                                       | root-causing live incidents, reviewing fork patches before deploy                                              |
| **Inside, a small fast model**                                      | cheap, fast, always available                                                                                     | scouting (`optio-scout`), running skills/runbooks, mechanical edits, tests, build + publish                    |

On hard bugs inside, run the main session on Claude and keep the scout on the small model (`model: haiku` in
`.claude/agents/optio-scout.md`, alias mapped in `.claude/settings.local.json`): Claude's context gets
40-line context packs instead of file dumps, which also saves contract budget.

## Where should a problem be solved?

| Problem                                                                        | Solve                                            | Why                                                                        |
| ------------------------------------------------------------------------------ | ------------------------------------------------ | -------------------------------------------------------------------------- |
| Optio doesn't speak our product's API (Jira DC v2, GitLab self-managed quirks) | **Outside**, in the twin lab                     | reproducible with public containers; needs docs and a strong model         |
| Config, TLS, CA, network policy, `GITLAB_HOSTS`, outbound allow-list           | **Inside**                                       | depends on our hosts and certs; can't be reproduced outside                |
| New dependency / toolchain / Claude Code version                               | **Outside** (`scripts/offline/make-kit.sh`)      | needs internet                                                             |
| Upstream sync + guide refresh (~345 upstream commits/month)                    | **Outside**                                      | needs the whole repo in context; the small model gets the distilled result |
| Live incident                                                                  | **Inside** (contract Claude + small-model scout) | needs logs                                                                 |
| Generic gap (Jira DC, chart `extraEnv`, CA in agent images)                    | **Outside → upstream PR**                        | every patch upstream accepts is one less fork patch to carry               |

## The loop

```
INSIDE                                   OUTSIDE
symptom ──► symptom card (by hand) ───►  twin lab: reproduce at the same commit
                                          patch + tests (+ upstream PR)
                                          refresh guides, check-agent-guides.sh
apply drop ◄─ transfer ◄─ drop (git bundle [+ kit]) + DROP.md
verify, impact.sh, rebuild, publish
```

### 1. Symptom card (inside → outside, typed by hand)

Only what is needed to reproduce. No hostnames, IPs, user names, tokens, internal URLs or log dumps.

```
Optio commit: <short sha of the running images>
Component: GitLab | Jira | agent pod | build | helm | other
Product + version: e.g. Jira Data Center 9.12, GitLab CE 17.x self-managed on port 8443
Error signature: <the exact message, identifiers replaced by HOST / PROJECT / ID>
Where it appears: API log | task log | UI | build output
Already tried: <config changes>
```

### 2. Twin lab (outside)

A disposable copy of our shape, at the same commit:

- a kind or k3d cluster; Optio via `helm/optio` with values that mirror ours structurally
  (`outbound.allowedHosts`, private CA, `existingSecrets`), no real data
- GitLab CE in a container with a self-signed CA on a non-443 port (mirrors our TLS + `host:port` cases)
- Jira Software Data Center in a container on an evaluation license, when the issue is Jira
- LiteLLM in front of a cheap model, routed the same way our pods are
- `scripts/offline/check-offline-build.sh` proves the build works with no network

Prompt to start outside Claude:

> Optio fork at `<sha>` (branch airgap/main, bundle attached). Here is a symptom card: … Reproduce it in
> the twin lab, write a failing test first (follow the style of the file's existing `.test.ts`), fix it
> with the smallest change, mark it `// AIRGAP-FORK:`, and tell me if it should go upstream.

### 3. Drop (outside → inside through your approved transfer process)

```
drop-YYYYMMDD/
  optio.bundle    git bundle create optio.bundle <last-drop-tag>..airgap/main   (incremental)
  kit-<ver>/      only when dependencies changed (scripts/offline/make-kit.sh)
  DROP.md         what changed, why, which tests, which images to rebuild
  SHA256SUMS      sha256sum of everything above
```

Outside, after cutting a drop: `git tag drop-YYYYMMDD airgap/main` (next drop starts from it).

Inside:

```bash
sha256sum -c SHA256SUMS
git bundle verify optio.bundle
git fetch optio.bundle airgap/main:drop/YYYYMMDD
git merge drop/YYYYMMDD          # clean: drops never touch docs/airgap/site-facts.md
bash scripts/check-agent-guides.sh
bash scripts/airgap/impact.sh HEAD@{1}..HEAD
```

then skill `optio-rebuild-publish`.

## Keeping the guides fresh (outside, each upstream bump)

Prompt for outside Claude, run on the mirror after merging upstream:

> In this Optio fork, run `scripts/check-agent-guides.sh`. Fix every MISSING path in the guides and add
> every INFO (unindexed) service module to `apps/api/src/services/AGENTS.md` under the right group. Read
> `git diff <old>..<new> -- AGENTS.md` and copy any new rule an agent must follow into the root `CLAUDE.md`
> (keep it under 150 lines). Re-check the "Known chart gaps" in `helm/CLAUDE.md` and the items in
> `docs/airgap/gotchas.md` against the new code; delete the ones upstream fixed.

## If an outbound path is ever approved

Keep the same split. Send symptom cards and test results, never raw logs or configs; review each
transfer as a human. The inside stays the only place that knows our hosts and secrets.
