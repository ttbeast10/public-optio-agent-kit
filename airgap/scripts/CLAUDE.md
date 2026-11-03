@AGENTS.md

## Air-gapped fork notes

| Script                                                                                                       | Use                                                                      |
| ------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `scripts/airgap/impact.sh [range]`                                                                           | changed files → images to rebuild, Helm keys, offline kit needed?, tests |
| `scripts/check-agent-guides.sh`                                                                              | every path named in the guides exists; unindexed services                |
| `scripts/offline/build-images.sh <TAG> --offline --registry <REG> --toolchain-version <KIT> --only … --push` | our image build                                                          |
| `scripts/offline/load-kit.sh`                                                                                | push a newly arrived offline kit into our registry                       |

`scripts/offline/make-kit.sh` needs internet: it runs on a connected host, and the kit comes in through your approved transfer process.
Do not use `setup-local.sh`, `update-local.sh` or `smoke-e2e.sh` against Rancher.
