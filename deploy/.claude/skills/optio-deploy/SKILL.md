---
name: optio-deploy
description: Runbook to install, upgrade, roll back or troubleshoot the Optio deployment from its Helm chart and images (no source code) — bundle, mirror, CA images, Kubernetes objects, helm, database-only bootstrap, verification, and a symptom table. Use for any change to how Optio runs, a new Optio version, or "Optio is broken".
---

# Deploy Optio (chart + images)

Read `site/site-facts.md` first. Every step is a script with a `--dry-run` or a read-only check: run that
first and show the user what will change. Phase numbers match `README.md`.

## First install

1. **Bundle (outside).** A person runs `bundle/fetch.sh <V> <presets…>` on an internet machine and carries
   the folder in. You can't do this step; check it was done: `ls <bundle>/MANIFEST.txt`.
2. **Load.** `bundle/load.sh <bundle>` → images in the registry, `bundle/optio-<V>.tgz`, `bundle/backup/`.
   Set `OPTIO_VERSION` in `site/deploy.env`.
3. **Cluster prerequisites** (once, by the cluster admins; confirm each with the user):
   - `busybox:1.36` is hardcoded in the chart: nodes must pull `docker.io/library/busybox` from our mirror
     (RKE2 `registries.yaml` rewrite, README phase 3).
   - ingress-nginx allows snippet annotations, or plan B in README phase 4.
   - A TLS Secret `optio-tls` for the ingress host, from our CA.
4. **CA images.** Put our CA bundle at `CA_FILE`; `images/build-agent-ca.sh`; set
   `agent.image.tag: "<V>-<CA_TAG>"` in values.
5. **Values.** Fill every `<FILL` in `values/values.yaml`, `site/site.env`, `site/deploy.env`.
   `scripts/check-values.sh bundle/optio-<V>.tgz` must pass.
6. **Kubernetes objects.** `cp site/secrets.env.example site/secrets.env`; fill what you know;
   `scripts/make-k8s-objects.sh --generate --dry-run`, then without `--dry-run`. Tell the user to copy
   `OPTIO_ENCRYPTION_KEY` to the vault named in site facts now.
7. **Install.** `scripts/deploy.sh --dry-run`, then `scripts/deploy.sh`. Then `scripts/verify.sh`.
8. **First sign-in** (a person): sign in as a `deploymentAdmins` address; Settings → API keys → make a
   key; `export OPTIO_TOKEN=…` in the shell.
9. **Database-only.** `scripts/bootstrap-db.sh`; do the UI steps it prints.
10. **Config.** Fill `config/`, `scripts/apply-config.sh --dry-run`, then `--sync`. Then
    `scripts/verify.sh --agent` and one manual run in the UI.

## Upgrade to a new version V2

Read upstream's release notes for every version between (the user brings them in with the bundle).
Then: phases 1–2 for V2 → `images/build-agent-ca.sh` with the new `OPTIO_VERSION` (CA_TAG may stay) →
update the image tags in values → `scripts/check-values.sh bundle/optio-<V2>.tgz` (new chart keys may
need values; removed ones must go) → `scripts/deploy.sh` (pre-upgrade dump first) → `scripts/verify.sh
--agent`. Running agent pods keep their old image until they are recycled.

## Roll back

The API migrates the database at boot, so the old version may not run against it. Ask the user first.
`bundle/backup/restore-db.sh --namespace <NS> --list` → `helm rollback <REL> <revision>` →
`bundle/backup/restore-db.sh --namespace <NS> latest-pre-upgrade` (it stops the API, restores, starts
it, checks the encryption key) → `scripts/verify.sh`.

## Symptoms

| Symptom                                                  | Look at / fix                                                                                 |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| postgres/redis pod `Init:ImagePullBackOff` on `busybox`  | the node mirror rewrite for docker.io (phase 3)                                               |
| agent pod `ImagePullBackOff`                             | registry auth for agent pods: SA `optio-agent` pull secret, or node `registries.yaml` auth    |
| API pod `CreateContainerConfigError`                     | an `existingSecrets` key missing: `kubectl describe pod`; `make-k8s-objects.sh`               |
| API pod stuck `ContainerCreating`                        | ConfigMap `optio-config` or `optio-site-ca` missing                                           |
| helm fails: ingress "snippet … cannot be used"           | README phase 4 (allow snippets, or plan B)                                                    |
| `unable to get local issuer certificate` in API log      | `NODE_EXTRA_CA_CERTS` in `site/site.env` + ConfigMap `optio-site-ca`; then `deploy.sh`        |
| same error inside an agent run, or `git clone` SSL error | the agent image tag in values isn't the `-caN` one; `verify.sh --agent`                       |
| `blocked: host resolves to a private address`            | `outbound.allowedHosts` in values                                                             |
| agent run hangs on git / gateway / npm, then times out   | `networkPolicy.extraEgress`: CIDR and port of that host                                       |
| GitLab repo work: no credentials for host                | `GITLAB_HOSTS` must be the exact `host` or `host:port`                                        |
| GitLab events don't start work                           | the project webhook's secret = `GITLAB_WEBHOOK_SECRET`; its delivery log; `features.triggers` |
| config change not applied                                | `GET /api/config/status`: `lastSyncError`, per-file errors; Settings → Config as code         |
| Helm value change has no effect                          | Settings → Access / Sign-in hold an override; or the key is unknown (`check-values.sh`)       |

Logs: `kubectl -n <NS> logs deploy/<REL>-api -c api --tail=300`; an agent pod: `kubectl -n <NS> logs <pod>`.
If the fix needs Optio source, stop: write the symptom, the version and what you tried, and tell the user.
