@AGENTS.md

## Air-gapped fork notes

- Our Jira flavor is in `docs/airgap/site-facts.md`. If it is Server/Data Center, upstream's Cloud-only
  provider fails (404 on search, 401 on auth). Plan and checks: skill `optio-debug-jira`.
- The Jira host must be in Helm `outbound.allowedHosts`; the base URL must be the final URL (https, with
  context path) because redirects are refused.
- Mark any change `// AIRGAP-FORK: Jira DC support` and keep the Cloud path working (upstream-able).
