@AGENTS.md

## Air-gapped fork notes

Our site values are not in this repo: see `docs/airgap/site-facts.md`. Look a value or env var up in
`helm/VALUES-MAP.md` first; it is regenerated on every kit install and by `bash scripts/helm-value-map.sh`.

| Key                                                                             | Why it matters here                                             |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `api.image`, `web.image`, `agent.image.prefix`, `agent.image.tag`               | our registry; one agent tag for base + dind + presets           |
| `imagePullSecrets`, `postgresql.image`, `redis.image`, `agent.envoyProxy.image` | mirror and pull from our registry                               |
| `agent.imagePullPolicy`                                                         | the one the API uses (`agent.image.pullPolicy` is not read)     |
| `outbound.allowedHosts` (or `outbound.allowPrivate`)                            | API calls to internal GitLab / Jira / IdP are blocked until set |
| `webhook.gitlabSecret`, `webhook.jiraSecret`                                    | must equal the secret on the GitLab / Jira webhook              |
| `agent.git.botName`, `agent.git.botEmail`                                       | commit identity on our GitLab                                   |
| `auth.oidc.caPem`, `auth.ldap.caPem`                                            | private CA for company sign-in                                  |
| `existingSecrets`                                                               | the only way to set env the chart has no value for              |
| `api.extraVolumes`, `api.extraVolumeMounts`                                     | mount our CA bundle into the API pod                            |
| `networkPolicy.enabled`, `networkPolicy.extraEgress`                            | agent pod egress to internal hosts                              |

Env vars we need that the chart cannot set (see "never sets" in `helm/VALUES-MAP.md`): `GITLAB_HOSTS`,
`GITLAB_OAUTH_BASE_URL`, `GITLAB_TOKEN` (deployment-wide), and `NODE_EXTRA_CA_CERTS` (read by Node itself, so
not in the map). Options: `existingSecrets`, or the fork patch `api.extraEnv` in `docs/airgap/gotchas.md` §3.
`auth.gitlab.baseUrl` is only a comment in `values.yaml`. If Rancher manages the release, change values in
Rancher → Apps → Edit YAML (one source of truth).
