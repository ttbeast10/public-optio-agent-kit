# Optio from its chart and images — deployment plan

Run [Optio](https://github.com/jonwiggins/optio) inside an air gap with **only the released Helm chart
and images**: no source code, no source changes. Its work is defined **as code** in `config/`. This
folder is a starter for your own internal deploy repo, written so that a person and a coding agent
(Claude Code, with `CLAUDE.md` and the two skills here) can carry it out together.

Checked against upstream Optio `d72f1cd1` (2026-11-01) and its chart in release `0.23.0`. `LDAP` sign-in
needs a newer release than `0.23.0`.

## Start

```bash
./deploy/init.sh /path/to/optio-deploy      # copies this folder into your deploy repo (git init'ed)
```

Re-running updates the scripts, skills, templates and this README. It never overwrites `values/`,
`config/` or `site/site-facts.md` (yours once copied), and never touches your filled `site/*.env`.
`bundle/fetch.sh` also runs from this public kit as is, on the internet side.

## Where configuration lives

| Layer                 | What                                                                      | Changed with                         |
| --------------------- | ------------------------------------------------------------------------- | ------------------------------------ |
| Helm values           | images, sign-in, ingress, network policy, data stores, agent pod defaults | `values/values.yaml` → `deploy.sh`   |
| Kubernetes Secrets    | encryption key, webhook secrets, env the chart has no value for, our CA   | `site/*.env` → `make-k8s-objects.sh` |
| Configuration as code | work (scheduled / event tasks, jobs, agents), prompts, repos, connections | `config/` → `apply-config.sh`        |
| Optio's database only | secret values work uses, users, workspaces, roles, ticket providers       | `bootstrap-db.sh`, the UI            |

Settings saved in Optio's UI under Access or Sign-in override the matching Helm values.

## The plan

Each phase ends with a check. The skill `optio-deploy` walks the same steps.

### Phase 0 — Decide (record the answers in `site/site-facts.md`)

| Decision                 | Options                                                                   | Suggested                                  |
| ------------------------ | ------------------------------------------------------------------------- | ------------------------------------------ |
| Optio version `V`        | a release tag; the chart and all images share it                          | the newest release                         |
| Who runs `helm`          | helm CLI from this repo · Rancher Apps (`questions.yaml`) · a GitOps tool | helm CLI (see "Known gaps": Argo CD)       |
| Sign-in                  | our GitLab (OAuth) · OIDC · LDAP (releases after `0.23.0`)                | GitLab, if it is the company's identity    |
| Agent image presets      | `base` + `node`, `python`, `go`, `rust`, `full`, `dind`                   | only what the repos need                   |
| Database                 | built-in PostgreSQL with backups to a PVC · an external one               | built-in, backups on                       |
| Jira                     | see "Jira" below                                                          | connection now, event trigger after a test |
| Ingress `/api/internal/` | allow nginx snippets · plan B (phase 4)                                   | whichever your cluster policy allows       |

### Phase 1 — Bundle (outside, a person with internet)

```bash
bundle/fetch.sh <V> node python      # needs helm, skopeo, curl
```

Produces `optio-bundle-<V>/`: the chart, the api / web / agent images, PostgreSQL, Redis, Envoy and the
`busybox` the chart hardcodes (all at the versions the chart pins), upstream's backup scripts, a manifest
and checksums. No site data goes out. Carry the folder in through your approved transfer process.

### Phase 2 — Load (inside)

```bash
cp site/deploy.env.example site/deploy.env    # fill KUBE_CONTEXT, REG_OPTIO, REG_MIRROR, …
bundle/load.sh /media/optio-bundle-<V>               # checksums, push images, chart → bundle/
```

Check: `bundle/optio-<V>.tgz` exists and the registry lists the images.

### Phase 3 — Cluster prerequisites (cluster admins, once)

1. **`busybox` from our mirror.** The chart's PostgreSQL / Redis init containers and its `helm test`
   pods use `busybox:1.36` with no value to change it. Point docker.io at the mirror on every node. RKE2
   (`/etc/rancher/rke2/registries.yaml`, or Rancher → cluster → Edit config → Registries):

   ```yaml
   mirrors:
     docker.io:
       endpoint: ["https://registry.example.com"]
       rewrite:
         "^library/(.*)": "mirror/library/$1"
   ```

2. **Registry auth.** Either the nodes authenticate (`configs:` in the same file) — then remove
   `imagePullSecrets` from the values and leave `REGISTRY_*` empty — or `make-k8s-objects.sh` makes the
   pull secret `optio-registry` and gives it to the agent ServiceAccount: the API sets no pull secret on
   agent pods itself.
3. **Ingress TLS.** A `kubernetes.io/tls` Secret `optio-tls` in the namespace, from our CA, for the
   Optio host name; and the DNS record.
4. **Storage.** A default StorageClass, or set `storageClass` in the values (PostgreSQL, Redis, backups,
   one home PVC per repo pod).

### Phase 4 — Ingress and `/api/internal/`

The chart's Ingress carries an nginx `server-snippet` that hides `/api/internal/` (token-auth endpoints
for pods) from outside traffic. ingress-nginx 1.9 and later disallow snippet annotations by default: its
admission webhook rejects the Ingress (the release fails), or, without the webhook, the snippet is
dropped and `/api/internal/` stays reachable. Check which applies, then either:

- **A — allow snippets** on the controller (cluster-wide; a security decision for the cluster owners).
  RKE2: a `HelmChartConfig` for `rke2-ingress-nginx` with `controller.allowSnippetAnnotations: true` and
  `controller.config.annotations-risk-level: Critical`.
- **B — own Ingress.** `ingress.enabled: false`, and keep in this repo an Ingress with the three paths
  (`/` → `<REL>-web:3000`, `/api` and `/ws` → `<REL>-api:4000`) plus a fourth, `/api/internal`, pointing
  at a Service that selects no pods (nginx answers 503). Apply it with `kubectl apply` after `deploy.sh`.

### Phase 5 — Install

1. **CA images.** Our CA bundle at `site/ca.crt`, then `images/build-agent-ca.sh` → every preset as
   `<V>-ca1` (upstream image + our CA, for git, Node, Python and pip). Agent pods can't mount a CA: the
   API builds their spec.
2. **Values.** `cp site/site.env.example site/site.env`; fill every `<FILL` there and in
   `values/values.yaml`. Check:
   `scripts/check-values.sh bundle/optio-<V>.tgz`.
3. **Secrets and objects.** `cp site/secrets.env.example site/secrets.env`, fill what you have, then
   `scripts/make-k8s-objects.sh --generate`. Copy `OPTIO_ENCRYPTION_KEY` to the team vault now: backups
   can't be read without it.
4. **Deploy.** `scripts/deploy.sh --dry-run`, then `scripts/deploy.sh`.
5. **Check.** `scripts/verify.sh`: Deployments ready, `/api/health` through the ingress, the API trusts
   our CA, the agent NetworkPolicy exists.

### Phase 6 — Bootstrap and configuration as code

1. **First sign-in** with an address in `auth.deploymentAdmins`. It creates the organization's
   workspace, which `config/` is applied to. Settings → API keys → a key; `export OPTIO_TOKEN=…`.
2. **Database-only secrets.** Fill the `DB_SECRET_*` lines (gateway key and URL, `JIRA_PAT`, package
   mirrors), then `scripts/bootstrap-db.sh`. Do the UI steps it prints.
3. **Config.** Adapt `config/` (examples: a repo, a GitLab issue → merge request task, a nightly
   dependency update, a Jira connection, a Jira-triggered task that is off), then
   `scripts/apply-config.sh --sync`. Check: no errors in the summary.
4. **GitLab webhook** per project: URL `<publicUrl>/api/webhooks/gitlab`, secret token
   `GITLAB_WEBHOOK_SECRET`, the events your `config/` listens to. Test it from GitLab.
5. **Jira test** (only if you want Jira to start work): a Jira webhook to `<publicUrl>/api/webhooks/jira`
   with the secret `JIRA_WEBHOOK_SECRET`; enable `config/work-jira-labeled.yaml` on a test project.
6. **Smoke.** `scripts/verify.sh --agent` (agent image pull, CA, egress to GitLab and the gateway), then
   label one test issue `optio` and follow the run to a merge request.

### Phase 7 — Operate

- **Change work:** edit `config/`, commit, `scripts/apply-config.sh --sync` (skill
  `optio-config-as-code`).
- **Change the deployment:** edit values or `site/`, commit, `make-k8s-objects.sh` if `site/` changed,
  `scripts/deploy.sh`.
- **Upgrade:** phases 1–2 for the new version, `build-agent-ca.sh`, new tags in values,
  `check-values.sh`, `deploy.sh` (it dumps the database first), `verify.sh --agent`.
- **Roll back:** `helm rollback` and `bundle/backup/restore-db.sh … latest-pre-upgrade` together; the
  API migrates the database at boot. Practise once with `restore-db.sh --into-database` (a drill).

## Known gaps, and the configuration that covers each

| Gap in chart or images (at `d72f1cd1`)                                  | Covered by                                                                                                                          |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `busybox:1.36` hardcoded in init containers and tests                   | node registry rewrite (phase 3)                                                                                                     |
| no pull secret on agent pods                                            | our ServiceAccount `optio-agent` with one, or node registry auth                                                                    |
| no free-form API env, no CA-bundle value (comments mention one)         | `existingSecrets` for any env var; `api.extraVolumes` for the CA file                                                               |
| agent images trust only public CAs, and pods can't mount one            | `images/agent-ca.Dockerfile`: upstream image + our CA (no source)                                                                   |
| agent NetworkPolicy always blocks private ranges, allows only 80 / 443  | `networkPolicy.extraEgress` per internal host and port                                                                              |
| nginx `server-snippet` on the Ingress                                   | phase 4                                                                                                                             |
| no "Anthropic base URL" setting for Claude Code                         | secret `ANTHROPIC_BASE_URL`, given to pods as env (`bootstrap-db.sh`)                                                               |
| Jira as a ticket source is Jira Cloud only (REST v3, email + API token) | see "Jira"                                                                                                                          |
| TLS certs and the Redis password are made once with Helm `lookup`       | install with helm or Rancher Apps; Argo CD renders with `helm template`, where `lookup` finds nothing, so they change on every sync |
| the chart takes the built-in PostgreSQL password only as a value        | `deploy.sh` passes it from `site/secrets.env` (it is kept in Helm's release Secret)                                                 |
| config directory comes from a ConfigMap: flat, ≤ 1 MiB                  | `<kind>-<name>.yaml` names; past 1 MiB mount a volume via `api.extraVolumes`                                                        |

## Jira

- **Agents read and update Jira — works now.** `config/connection-jira.yaml` uses the built-in "HTTP API"
  provider: a REST bridge already in the agent images, pointed at Jira's REST API v2 with a personal
  access token. Add it to work with `environment.connections.add: [Jira]`.
- **Jira events start work — test first.** `when: jira` listens on `/api/webhooks/jira` and checks an
  `X-Hub-Signature` HMAC. Whether your Jira version signs webhooks and sends the payload Optio expects is
  what phase 6.5 shows. If not: a scheduled task whose prompt searches Jira through the connection.
- **Jira Data Center as a `ticket` source — needs code.** Out of scope for this setup.

## What only a person can do

Carry the bundle in; the cluster prerequisites; the first sign-in and the API key; inviting people and
roles; GitLab and Jira webhooks; storing the encryption key copy; approving every upgrade and restore.
