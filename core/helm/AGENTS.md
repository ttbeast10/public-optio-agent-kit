# helm/optio — the Helm chart

## What it is

The chart that deploys Optio's control plane: the API pod (two containers, `api` and `web`), optional
bundled Postgres and Redis, the Secret that configures the API, RBAC, network policies, ingress or Gateway
API routes, metrics and alerting, a database backup job, and the Rancher Apps form. **Agent pods are not in
the chart**: the API creates them at run time from the `agent.*` values it receives as env vars.

The full value → template → env var → code table is `helm/VALUES-MAP.md`, generated from this chart.
Grep it before reading templates: `grep -n "outbound" helm/VALUES-MAP.md`.

## Main ideas

- **Most values become env vars of the API container.** They are rendered into the `<release>-config`
  Secret (`helm/optio/templates/secrets.yaml`) and loaded with `envFrom`; a few are set inline in
  `helm/optio/templates/api-deployment.yaml`. The API reads them with `process.env` (see the map's "Read by").
- **`existingSecrets` maps an env var name to a key in a Secret you own**, so a value never enters the Helm
  release. It is also the only way to set an env var the chart has no value for: the map lists those under
  "Env vars the API reads that the chart never sets".
- **`api.env` renders only `LOG_LEVEL`.** Other keys under `api.env` are ignored.
- **Not everything in `values.yaml` does something.** The map's last section lists keys no template reads.
- **Agent pods are configured indirectly.** `agent.image.prefix` + `agent.image.tag` name every agent image
  (`{prefix}{preset}:{tag}`: base, dind and each language preset share one tag); `agent.pvc`, `agent.cache`,
  `agent.nodeSelector`, `agent.tolerations`, `agent.statefulSet`, `agent.rootless`, `agent.git` and
  `agent.envoyProxy` become `OPTIO_*` env vars that `apps/api/src/services/repo-pool-service.ts` and its
  neighbours use when they create StatefulSets and PVCs. `agent.serviceAccount` is a separate identity from
  the API's `serviceAccount`, with no API RBAC.
- **Data stores: bundled or external.** `postgresql.enabled` / `redis.enabled` run them in the release
  (Deployments, optional TLS with generated certs kept across upgrades by `lookup`). Otherwise
  `externalDatabase.url` / `externalRedis.url` (or `existingSecrets.DATABASE_URL` / `REDIS_URL`) point at
  managed services; `externalRedis.mode: cluster` switches the API to Redis Cluster.
- **One API pod type, any number of replicas.** `api.replicas` or `api.autoscaling` (HPA), `api.pdb`,
  `api.antiAffinity`. Rollouts always use Recreate, because migrations run at boot.
- **Reaching it.** `ingress.*` or `gatewayAPI.*` (one or the other), `publicUrl` and `web.publicApiUrl` for the
  URLs the API advertises; `api.service` / `web.service` set NodePort for local clusters.
- **Who may call out.** `outbound.allowPrivate` / `outbound.allowedHosts` decide which private hosts the API
  may call for URLs people typed (repo validation, ticket providers, webhooks, health checks).
  `networkPolicy.*` restricts what agent pods may reach; `metrics.networkPolicy` who may scrape.
- **Operations.** `metrics.*` (ServiceMonitor, PrometheusRule, Grafana dashboard), `observability.otel.*`
  (OpenTelemetry export), `backup.*` (a CronJob that dumps Postgres to a PVC or S3; `docs/backup.md`),
  `resourceQuota.*`, `configAsCode.*` (a ConfigMap of manifests the API applies; `docs/config-as-code.md`).
- **Features and sign-in.** `features.*` (which runtimes, platforms, triggers, ticket sources, connections
  are offered), `auth.*` (OAuth providers, OIDC, LDAP, setup token, deployment admins), `webhook.*` (signing
  secrets of incoming webhooks), `github.app.*`, `workspaces`, `onboarding`, `prompts`, `tickets`.
- **Secrets survive upgrades.** `encryption.key` encrypts every stored secret: it must never change. Generated
  passwords and certificates are reused through `lookup`, so `helm template` output differs from an install.

## Where things are

| Path                                                                                                            | What                                            |
| --------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `helm/optio/values.yaml`                                                                                        | every setting with comments — grep it           |
| `helm/VALUES-MAP.md`                                                                                            | generated value → template → env var → code     |
| `helm/optio/templates/_helpers.tpl`                                                                             | shared helpers: names, labels, URLs, features   |
| `helm/optio/templates/secrets.yaml`                                                                             | the config Secret: most env vars                |
| `helm/optio/templates/api-deployment.yaml`                                                                      | the API pod: containers, inline env, volumes    |
| `helm/optio/templates/web-deployment.yaml`                                                                      | the web Service (the container is in the pod)   |
| `helm/optio/templates/agent-pvc.yaml`                                                                           | agent PVC template the API reads at run time    |
| `helm/optio/templates/postgres.yaml`, `helm/optio/templates/redis.yaml`                                         | bundled data stores (+ `*-tls.yaml`)            |
| `helm/optio/templates/rbac.yaml`, `helm/optio/templates/agent-service-account.yaml`                             | API permissions; agent identity                 |
| `helm/optio/templates/network-policy.yaml`                                                                      | agent pod egress                                |
| `helm/optio/templates/ingress.yaml`, `helm/optio/templates/gateway.yaml`, `helm/optio/templates/httproute.yaml` | exposure                                        |
| `helm/optio/templates/hpa.yaml`, `helm/optio/templates/pdb.yaml`                                                | scaling and availability                        |
| `helm/optio/templates/servicemonitor.yaml`, `helm/optio/templates/prometheusrule.yaml`                          | metrics and alerts (+ `grafana-dashboard.yaml`) |
| `helm/optio/templates/backup-cronjob.yaml`                                                                      | Postgres backups                                |
| `helm/optio/templates/tests/`                                                                                   | `helm test` connection and metrics checks       |
| `helm/optio/questions.yaml`                                                                                     | Rancher Apps form                               |
| `helm/optio/values.local.yaml`, `helm/optio/values.production.yaml`                                             | examples                                        |

## Change it safely

- Lint: `helm lint helm/optio --set encryption.key=test`
- Render one template: `helm template t helm/optio --set encryption.key=test -s templates/api-deployment.yaml`
- New setting the API reads: add the value to `values.yaml`, render it in `secrets.yaml` (or inline in
  `api-deployment.yaml`), read it in the API, then `bash scripts/helm-value-map.sh` to refresh the map.
- A chart change needs no image rebuild, only `helm upgrade` (`--reuse-values` keeps earlier values).
- `bash scripts/check-agent-guides.sh` fails while `helm/VALUES-MAP.md` is out of date.
