@AGENTS.md

## Air-gapped fork notes

- Build agent images with `scripts/offline/build-images.sh --offline` (never `images/build.sh`, it downloads).
  `--only agent-base,agent-dind,agent-node,agent-python,agent-go,agent-rust,agent-full` — all of them, one tag.
- Smaller images: `--agent-clis claude-code,opencode`; OpenCode from our npm mirror: `--opencode-install-method npm`.

### Corporate CA (internal GitLab / Jira / LiteLLM)

Upstream agent images trust only public CAs, so `git clone` from our GitLab fails TLS.
Fork patch in `images/base.Dockerfile`, final stage, right after `USER root`:

```dockerfile
# AIRGAP-FORK: trust the corporate CA for git, curl, node and the agent CLIs
COPY images/corp-ca/ /usr/local/share/ca-certificates/corp/
RUN update-ca-certificates
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt
```

Create the folder images/corp-ca with the PEM file(s) named `*.crt`. Works with `--offline`.
The API pod needs the same CA: `docs/airgap/gotchas.md` §2.
