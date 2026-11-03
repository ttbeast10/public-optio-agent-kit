<!-- Owned by the team, inside the air gap. The kit installs it once and never overwrites it.
     Imported by the root CLAUDE.md, so keep it short. Never put secret values here. -->

| Fact                                    | Value                                                                         |
| --------------------------------------- | ----------------------------------------------------------------------------- |
| Fork remote / branch                    | `<FILL: e.g. origin / airgap/main>`                                           |
| Upstream base commit                    | `<FILL: short sha>` (also in the offline kit's `KIT.md`)                      |
| Offline kit version (`KIT`)             | `<FILL: e.g. 1.0.0>` — pass as `--toolchain-version`                          |
| Registry (`REG`)                        | `<FILL: e.g. registry.corp/optio>`                                            |
| Helm release (`REL`) / namespace (`NS`) | `<FILL: optio>` / `<FILL: optio>`                                             |
| Release managed by Rancher Apps?        | `<FILL: yes/no>`                                                              |
| Kube context (Rancher)                  | `<FILL>`                                                                      |
| Site Helm values file                   | `<FILL: where it lives>`                                                      |
| Postgres                                | `<FILL: bundled (postgresql.enabled) or external>` — DB user / name: `<FILL>` |
| GitLab host[:port]                      | `<FILL>`                                                                      |
| Jira URL and flavor                     | `<FILL: https://jira.corp[/context]>` — `<FILL: Server/DC or Cloud>`          |
| LLM gateway                             | `<FILL: LiteLLM URL>` — small-model alias `<FILL>`, Claude alias `<FILL>`     |
