#!/usr/bin/env bash
# Smoke checks after a deploy. Read-only, except the short-lived smoke pod (--agent).
#
#   scripts/verify.sh [--agent]
#
#   always   the release's Deployments are ready; /api/health answers through the ingress with our CA;
#            the API pod trusts our CA (a TLS call to GitLab); the agent NetworkPolicy exists;
#            with OPTIO_TOKEN: the config-as-code status (last sync, errors)
#   --agent  start one pod the way Optio starts agent pods (agent image with our CA, ServiceAccount
#            optio-agent, label managed-by=optio so the NetworkPolicy applies) and call GitLab and
#            the LLM gateway from it: proves image pull, CA trust and egress in one go
# Needs kubectl and curl.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

agent=0
[ "${1:-}" = --agent ] && agent=1
load_deploy_env
pass=0 fail=0
ok() { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }

for d in api postgres redis; do
  if kube_ns get deploy "$RELEASE-$d" >/dev/null 2>&1; then
    kube_ns rollout status "deploy/$RELEASE-$d" --timeout=120s >/dev/null 2>&1 \
      && ok "deploy/$RELEASE-$d ready" || bad "deploy/$RELEASE-$d not ready (kubectl -n $NAMESPACE describe deploy/$RELEASE-$d)"
  fi
done

ca=()
[ -f "$CA_FILE" ] && ca=(--cacert "$CA_FILE")
curl -fsS "${ca[@]}" -o /dev/null "$OPTIO_SERVER/api/health" \
  && ok "$OPTIO_SERVER/api/health" || bad "$OPTIO_SERVER/api/health (ingress, TLS or the API)"

gitlab_url="$(env_get site/site.env GITLAB_OAUTH_BASE_URL)"
[ -n "$gitlab_url" ] || gitlab_url="https://$(env_get site/site.env GITLAB_HOSTS | cut -d, -f1)"
probe='fetch(process.argv[1]).then(r=>{console.log(r.status)}).catch(e=>{console.error(e.cause?.code||e.message);process.exit(1)})'
if out="$(kube_ns exec "deploy/$RELEASE-api" -c api -- node -e "$probe" "$gitlab_url" 2>&1)"; then
  ok "API pod reaches $gitlab_url over TLS (HTTP $out)"
else
  bad "API pod → $gitlab_url: $out (CA: NODE_EXTRA_CA_CERTS + optio-site-ca; network: outbound.allowedHosts)"
fi

kube_ns get networkpolicy "$RELEASE-repo-pod-policy" >/dev/null 2>&1 \
  && ok "agent NetworkPolicy present" || bad "agent NetworkPolicy missing (networkPolicy.enabled)"

if [ -n "${OPTIO_TOKEN:-}" ]; then
  status="$(api_call GET /api/config/status || true)"
  if echo "$status" | grep -q '"enabled":true'; then
    err="$(echo "$status" | grep -oE '"lastSyncError":("[^"]*"|null)' | head -1)"
    sum="$(echo "$status" | grep -oE '"summary":\{[^}]*\}' | head -1)"
    [[ "$err" == *null* || -z "$err" ]] && ok "config as code: $sum" || bad "config as code: $err"
  else
    bad "config as code is not enabled on the API (configAsCode.enabled / the optio-config mount)"
  fi
else
  echo "skip  config-as-code status (export OPTIO_TOKEN to check it)"
fi

if [ "$agent" = 1 ]; then
  image="$REG_OPTIO/optio-agent-base:$OPTIO_VERSION-$CA_TAG"
  gateway="$(env_get site/secrets.env DB_SECRET_ANTHROPIC_BASE_URL)"
  pod="optio-smoke-$(date +%s)"
  script='for u in "$@"; do node -e "fetch(process.argv[1]).then(r=>console.log(\"ok \"+process.argv[1]+\" \"+r.status)).catch(e=>{console.log(\"FAIL \"+process.argv[1]+\" \"+(e.cause?.code||e.message));process.exitCode=1})" "$u"; done'
  overrides="{\"spec\":{\"serviceAccountName\":\"optio-agent\",\"automountServiceAccountToken\":false}}"
  if out="$(kube_ns run "$pod" --image="$image" --restart=Never --rm -i --quiet \
    --labels=managed-by=optio --overrides="$overrides" --command -- bash -c "$script" smoke \
    "$gitlab_url" ${gateway:+"$gateway"} 2>&1)"; then
    ok "agent pod ($image): $(echo "$out" | tr '\n' ' ')"
  else
    bad "agent pod ($image): $(echo "$out" | tr '\n' ' ') — pull: registry auth; FAIL with a cert code: the CA image; timeout: networkPolicy.extraEgress"
  fi
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
