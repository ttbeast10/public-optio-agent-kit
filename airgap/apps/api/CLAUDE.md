@AGENTS.md

## Air-gapped fork notes

- Calls the API makes to internal hosts (GitLab validation, Jira, webhooks, health checks) pass the outbound
  guard: allow them with Helm `outbound.allowedHosts` (`docs/airgap/gotchas.md` §1).
- The API trusts only public CAs unless `NODE_EXTRA_CA_CERTS` points at our CA bundle (gotchas §2).
- Env the chart cannot set (`GITLAB_HOSTS`, `GITLAB_OAUTH_BASE_URL`, `NODE_EXTRA_CA_CERTS`): gotchas §3.
- Read a live env var: `kubectl -n <ns> exec deploy/<release>-api -c api -- printenv GITLAB_HOSTS` (names, never secrets).
- After a change here: `bash scripts/airgap/impact.sh`, then skill `optio-rebuild-publish` (image `api`).
