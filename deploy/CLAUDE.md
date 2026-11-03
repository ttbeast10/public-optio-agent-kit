# Optio deployment — chart and images only, work as code

This repo runs [Optio](https://github.com/jonwiggins/optio) from its released Helm chart and images,
with its work, prompts, repos and connections defined as code in `config/`. There is no Optio source
code here and none is needed. If a task seems to need a code change, stop and tell the user: it is
either a gap to work around with configuration (see `README.md`, "Known gaps") or an upstream request.

@site/site-facts.md

## Rules

- Never put a secret value in a tracked file, a commit, a log you paste, or a reply. Secrets live in
  `site/secrets.env` (gitignored) and from there in Kubernetes Secrets or Optio's database. To check one
  exists, check the key (`kubectl get secret … -o jsonpath='{.data.KEY}' | wc -c`), never print it.
- `values/`, `config/` and `site/` belong to the team: change them on purpose and say why in the commit.
- Never change `OPTIO_ENCRYPTION_KEY` or `POSTGRES_PASSWORD` after the first install. Never re-push an
  image tag (nodes cache by tag): bump the version or `CA_TAG`.
- Upgrades go through `scripts/deploy.sh`, which takes a pre-upgrade database dump first. `helm rollback`
  alone is not a rollback: the new version has already migrated the database (skill `optio-deploy`).
- Ask the user before: `helm uninstall`, deleting a PVC or the namespace, `bundle/backup/restore-db.sh`,
  changing sign-in, deleting a manifest that has running work (prune deletes it), anything that stops
  running work. Read-only commands need no confirmation.
- Prefer `--dry-run` first: `deploy.sh`, `apply-config.sh` and `make-k8s-objects.sh` all have one.

## Where a setting lives — decide this before changing anything

| Setting                                                                   | File                                    | Applied by                              |
| ------------------------------------------------------------------------- | --------------------------------------- | --------------------------------------- |
| Images, sign-in, ingress, network policy, data stores, agent pod defaults | `values/values.yaml`                    | `scripts/deploy.sh`                     |
| API env the chart has no value for (`GITLAB_HOSTS`, CA path, …)           | `site/site.env`                         | `make-k8s-objects.sh`, then `deploy.sh` |
| Deploy-time secrets (encryption key, webhook secrets, GitLab token)       | `site/secrets.env`                      | `make-k8s-objects.sh`, then `deploy.sh` |
| Work (jobs, scheduled tasks, agents), prompts, repos, MCP, skills, conns  | `config/*.yaml` (+ `*.md` prompt files) | `scripts/apply-config.sh`               |
| Secrets work and connections use (gateway key, `JIRA_PAT`, mirrors)       | `site/secrets.env`, `DB_SECRET_<NAME>=` | `scripts/bootstrap-db.sh`               |
| Users, workspaces, roles, ticket providers, webhook-trigger secrets       | Optio's database                        | the UI, once                            |

A value saved in Optio's Settings → Access or Settings → Sign-in overrides the Helm value. If a Helm
change seems to have no effect, check there.

## Map

| Path                      | What                                                                          |
| ------------------------- | ----------------------------------------------------------------------------- |
| `README.md`               | the plan: phases 0–7, known gaps and their workarounds                        |
| `site/`                   | `site-facts.md`, `deploy.env`, `site.env`, `secrets.env` (+ `.example`s)      |
| `values/values.yaml`      | the Helm values                                                               |
| `config/`                 | configuration as code — flat: a ConfigMap has no folders                      |
| `bundle/`                 | `fetch.sh` (outside), `load.sh` (inside); the chart and backup scripts        |
| `images/`                 | the agent image with our CA (`agent-ca.Dockerfile`, `build-agent-ca.sh`)      |
| `scripts/`                | `make-k8s-objects`, `deploy`, `apply-config`, `bootstrap-db`, `verify`        |
| `scripts/check-values.sh` | keys in our values that the carried-in chart doesn't know                     |
| `.claude/skills/optio-*`  | `optio-deploy` (install, upgrade, rollback, symptoms), `optio-config-as-code` |

## Looking at the running system

```bash
. site/deploy.env
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get pods
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" logs deploy/"$RELEASE"-api -c api --tail=200
kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" get pods -l managed-by=optio   # agent pods
helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" get values "$RELEASE"
scripts/verify.sh            # health, CA trust, network policy, config-as-code status
```

With `OPTIO_TOKEN` exported (an API key): `GET $OPTIO_SERVER/api/config/status` (last sync and errors)
and `GET $OPTIO_SERVER/api/config/schema.json` (every manifest field).
