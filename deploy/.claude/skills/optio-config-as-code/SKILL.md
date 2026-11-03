---
name: optio-config-as-code
description: How to add or change Optio work, prompts, repos, connections, MCP servers and skills as YAML manifests in config/, check them, publish them and confirm the sync. Use whenever someone wants Optio to do something new, on a schedule or on an event, or to change how a repo is handled.
---

# Optio configuration as code

The `config/` folder becomes the ConfigMap `optio-config`; the API reads it every minute and makes the
organization's workspace match it. The files win: a resource whose file is gone is deleted (prune), and
a UI edit to a managed resource is put back at the next sync.

## Rules

- `config/` is **flat**: no folders (a ConfigMap has none). Name files `<kind>-<name>.yaml`; a prompt file
  sits next to its manifest (`work-<name>.md`). `filesFrom` (a folder) can't be used here.
- One resource per document; several documents per file are allowed (`---`).
- `apiVersion: optio/v1` on every document. Identity: `metadata.name` (for `Repo`: `spec.url`).
  Renaming = delete + create (the run history goes).
- **No secret values in manifests.** Work lists pod secrets by name (`secrets: [NAME]`); a connection's or
  MCP server's secret field is `${{NAME}}`. The secret must exist first: `DB_SECRET_NAME=` in
  `site/secrets.env` + `scripts/bootstrap-db.sh`. An unknown name fails that manifest only.
- References are names: repos by URL (a `Repo` manifest registers it), connections / MCP servers / skills
  by name, runtime by id (`claude-code`). Only runtimes and triggers in `features` (values) work.
- Every agent run needs the gateway: `secrets: [ANTHROPIC_BASE_URL, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC]`
  and `who.model:` (or the repo's `claudeModel`) set to a model alias the gateway knows.

## Kinds (all fields: `GET $OPTIO_SERVER/api/config/schema.json`)

| Kind         | Use it for                                    | Key fields                                                                                        |
| ------------ | --------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Work`       | a scheduled task, an event-driven task, a Job | `when` (one key: `schedule`, `gitlab`, `jira`, `webhook`, …), `where.repo`, `who`, `what`, `then` |
| `Repo`       | a repo's defaults                             | `url`, `defaultBranch`, `imagePreset`, `claudeModel`, `setupCommands`, concurrency, resources     |
| `Prompt`     | a reusable prompt template                    | `kind`, `template` / `templateFile`                                                               |
| `Connection` | a service agents can call                     | `provider` (`custom-http` = any REST API, `custom-mcp`), `config`                                 |
| `McpServer`  | a hand-written MCP server                     | `command`, `args`, `env` (`${{SECRET}}`); the binary must already be in the agent image           |
| `Skill`      | a skill file for agents                       | `prompt` / `promptFile`, `agentTypes`                                                             |

`Work` shapes: `when` + `where.repo` = scheduled/event task (`then: until-merged` keeps it until the MR
merges); no `where.repo` = a Job; `then: waits-for-messages` + `agent:` = a persistent agent. A one-off
run (no `when`, a repo, `exits`) is not configuration and is refused.
Trigger configs: `gitlab: { events: [mr_opened|issue_opened|labeled|push|pipeline_failed|…],
projects: [group/project], labels: […], branches: […] }`; `jira: { events: [created|labeled|commented|
transitioned|…], projects: [KEY], labels: […] }`; `schedule: "<cron, UTC>"`.
Prompt params: gitlab `{{iid}} {{title}} {{body}} {{url}} {{project}} {{sourceBranch}} …`; jira
`{{key}} {{title}} {{description}} {{url}} …`. Examples: the files already in `config/`.

## Change → publish → confirm

1. Edit or add files in `config/`. Copy the closest existing example.
2. `scripts/apply-config.sh --dry-run` (local checks). With the Optio CLI installed, `--diff` also shows
   the server's plan.
3. Commit, then `scripts/apply-config.sh --sync`. It prints the summary: created / updated / pruned /
   errors.
4. Errors: `GET $OPTIO_SERVER/api/config/status` lists each one with its file. Fix and repeat.
5. Event work: send a test event (GitLab: project → Webhooks → Test) and watch the run in the UI.

To start from what someone built in the UI: Settings → Config as code → Export workspace as YAML, then
flatten it into `config/` (one file per resource, prompts as `*.md` next to them). A matching name is
adopted, not duplicated.
