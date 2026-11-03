# Air-gap gotchas (upstream Optio at d72f1cd1, 2026-11-01)

Each item: symptom → cause → fix. "Fork patch" = a change we carry; mark it `AIRGAP-FORK:` and consider upstreaming it.

## 1. API refuses internal hosts

- **Symptom:** `blocked: host resolves to a private address (10.x.x.x); set OPTIO_OUTBOUND_ALLOW_PRIVATE=true or list it in OPTIO_OUTBOUND_ALLOWED_HOSTS` — during GitLab validation, Jira sync, connection health checks, webhooks out.
- **Cause:** every URL the API fetches goes through `guardedFetch` (`packages/shared/src/utils/outbound-http.ts`) with an SSRF policy (`packages/shared/src/utils/ssrf.ts`).
- **Fix (Helm):** `outbound.allowedHosts: ["gitlab.corp", "jira.corp", "10.20.0.0/16"]` (preferred), or `outbound.allowPrivate: true`.
- Redirects are not followed for Jira (`redirect: "error"`): the Jira base URL must be the final URL (https, with context path such as `/jira` if your Jira has one).

## 2. TLS errors to internal services (private CA)

- **Symptom:** `unable to get local issuer certificate`, `self-signed certificate in certificate chain`, `SSL certificate problem` (git).
- **API pod:** Node only trusts public CAs. Mount the CA and set `NODE_EXTRA_CA_CERTS`:
  - mount: `api.extraVolumes` / `api.extraVolumeMounts` (a ConfigMap or Secret with `ca.crt`)
  - env: the chart has no free-form env (see 3) → fork patch `api.extraEnv`, or a Secret via `existingSecrets`.
- **Agent pods:** bake the CA into the agent image — snippet in `images/CLAUDE.md`.
- **Sign-in:** OIDC and LDAP have their own `caPem` values in `helm/optio/values.yaml`.

## 3. Chart can't set some env vars the API needs

- `api.env` renders only `LOG_LEVEL` (`helm/optio/templates/api-deployment.yaml`). There are no values for `GITLAB_HOSTS`, `GITLAB_OAUTH_BASE_URL`, `NODE_EXTRA_CA_CERTS`.
  The full list of env vars the API reads but the chart never sets is in `helm/VALUES-MAP.md`.
- **Workaround, no chart change:** create a Secret `optio-site-env` with those keys and map each one:
  ```yaml
  existingSecrets:
    GITLAB_HOSTS: { name: optio-site-env, key: GITLAB_HOSTS }
    GITLAB_OAUTH_BASE_URL: { name: optio-site-env, key: GITLAB_OAUTH_BASE_URL }
    NODE_EXTRA_CA_CERTS: { name: optio-site-env, key: NODE_EXTRA_CA_CERTS }
  ```
- **Fork patch (cleaner):** in `api-deployment.yaml`, inside the `api` container `env:` list, right after the `LOG_LEVEL` entry, indented like the `- name:` lines around it:
  ```yaml
              {{- /* AIRGAP-FORK: free-form env for the API container */}}
              {{- range $k, $v := .Values.api.extraEnv }}
              - name: {{ $k }}
                value: {{ $v | quote }}
              {{- end }}
  ```
  and `api.extraEnv: {}` in `values.yaml`. Then `helm lint helm/optio --set encryption.key=test`.

## 4. GitLab self-managed

- `GITLAB_HOSTS` must list the exact `host` or `host:port` (non-443 ports must be explicit). Unknown hosts get no token from the credential helper.
- Tokens: secret `GITLAB_TOKEN`, or per host `GITLAB_TOKEN_<HOST>_<PORT>` (uppercase, punctuation → `_`). See `docs/gitlab-tokens.md`.
- GitLab sign-in on a self-managed server needs `GITLAB_OAUTH_BASE_URL` (see 3).
- Webhook secret: `webhook.gitlabSecret` must equal the GitLab webhook's "Secret token".
- Triage: skill `optio-debug-gitlab`.

## 5. Jira Server / Data Center

- Upstream supports **Jira Cloud only**: REST API v3 (`/rest/api/3/search/jql`, Cloud-only), Basic auth with email + API token, comments in Atlassian Document Format.
- Server/DC has REST API v2 only, uses a Personal Access Token as `Authorization: Bearer`, and plain-text/wiki bodies.
- Needs a fork patch in `packages/ticket-providers/src/jira.ts`. Plan: skill `optio-debug-jira`.

## 6. LLM gateway (LiteLLM) for agents in pods

- Upstream has no "Anthropic base URL" setting for Claude Code. OpenCode has one (`OPTIO_OPENCODE_BASE_URL`, `agentOptions.opencodeBaseUrl` in `apps/api/src/services/pooled-agent-env.ts`).
- Pod secrets a piece of work picks become env vars of the same name (`resolvePodSecrets` in `apps/api/src/services/secret-service.ts`, used by `apps/api/src/workers/task-worker.ts`). So a secret named `ANTHROPIC_BASE_URL` (plus the gateway key as `ANTHROPIC_API_KEY`) can route Claude Code to LiteLLM. Verify on one run with `env | grep ANTHROPIC` inside the pod.
- Also give pods `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` the same way, so Claude Code doesn't wait on unreachable telemetry/update hosts.

## 7. Images and tags

- Never re-push an existing tag: nodes cache by tag (`IfNotPresent`) and long-lived repo pods keep the image they started with.
- `agent.image.tag` is shared by base, dind and all presets.
- Offline builds need `--toolchain-version <kit version>` whenever your image tag differs from the kit version.
- Any change to `package.json`, `pnpm-lock.yaml` or `patches/` needs a new offline kit: built on an internet-connected host with `scripts/offline/make-kit.sh` and brought in through your approved transfer process.
