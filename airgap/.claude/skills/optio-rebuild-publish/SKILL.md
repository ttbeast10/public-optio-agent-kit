---
name: optio-rebuild-publish
description: Runbook to ship a code change in the air-gapped Optio fork — verify, find what to rebuild, build images offline with a new tag, push to the internal registry, helm upgrade on Rancher, recycle agent pods, confirm. Use whenever a change must reach the running system.
---

# Rebuild and publish Optio (offline)

Read `docs/airgap/worklog.md` "Now". Take these from `docs/airgap/site-facts.md`:
`REG=<registry>  KIT=<offline kit version>  NS=<namespace>  REL=<helm release>`

## 0. Gate: dependencies

If `git diff --name-only <base>` shows `package.json`, any `*/package.json` dependency change, `pnpm-lock.yaml` or `patches/`:
**STOP.** A new offline kit is needed: made with `scripts/offline/make-kit.sh` on an internet-connected host,
brought in through your approved transfer process, loaded with `scripts/offline/load-kit.sh`. Tell the user.

## 1. Verify the change

- Typecheck each touched package: `pnpm --filter @optio/<pkg> typecheck`
- Run the tests next to every changed file: `pnpm --filter @optio/<pkg> exec vitest run <path/to/x.test.ts>`
- Chart changed: `helm lint helm/optio --set encryption.key=test`

## 2. What to rebuild

`bash scripts/airgap/impact.sh <base>..HEAD` (or no argument for uncommitted changes). It prints the `--only` list.

## 3. Pick a new, unique tag (never reuse one)

`TAG=af-$(date +%Y%m%d)-$(git rev-parse --short HEAD)`

## 4. Build and push

```bash
scripts/offline/build-images.sh "$TAG" --offline --registry "$REG" \
  --toolchain-version "$KIT" --only <list from impact.sh> --push
```

- Agent images: `--only agent-base,agent-dind,agent-node,agent-python,agent-go,agent-rust,agent-full` (all of them: Helm uses one agent tag). Check the list against `scripts/offline/presets.txt`.
- Builder flags (`--builder`, `--buildkit-host`) per the header of `scripts/offline/build-images.sh`.
- Built names: `<REG>/optio-api:<TAG>`, `<REG>/optio-web:<TAG>`, `<REG>/optio-agent-<name>:<TAG>`.

## 5. Deploy

Set only the tags you rebuilt; leave the others as they are.

```bash
helm upgrade "$REL" helm/optio -n "$NS" --reuse-values \
  --set api.image.tag="$TAG" --set web.image.tag="$TAG"      # api/web rebuilt
#  --set agent.image.tag="$TAG"                              # agent images rebuilt
```

If Rancher manages the release, make the same change in Rancher → Apps → Optio → Edit YAML instead (one source of truth).

## 6. Confirm

- `kubectl -n "$NS" rollout status deploy/"$REL"-api --timeout=5m` (Recreate strategy: brief downtime; migrations run at boot)
- Running images: `kubectl -n "$NS" get pods -l app=optio-api -o jsonpath='{range .items[*].spec.containers[*]}{.name}={.image}{"\n"}{end}'`
- Boot errors: `kubectl -n "$NS" logs deploy/"$REL"-api -c api --since=10m | grep -iE "error|migrat" | tail -30`

## 7. Agent images: recycle repo pods

Repo pods are long-lived and keep the image they started with.

- See what they run: `kubectl -n "$NS" get pods -l managed-by=optio -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image`
- When no run is active on a repo, delete its old StatefulSet (or bare pod): `kubectl -n "$NS" get statefulsets -l managed-by=optio`. The API creates a new one on the next run. Then run one small task and check its pod's image.

## 8. Report

```
Tag: <TAG>   Images: <list>   Helm: <keys changed>
Rollout: ok | failed (<log line>)   Agent pods recycled: yes/no/not needed
Smoke: <task id> → <state>
```

Then add one line to `docs/airgap/worklog.md` Log: `YYYY-MM-DD · publish · <TAG> · <images> · <result>`.
