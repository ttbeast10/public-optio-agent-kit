#!/usr/bin/env bash
# The Kubernetes objects the release reads but does not make, from the files in site/. Idempotent:
# run it before the first install and whenever site/*.env or the CA changes (then deploy.sh, so the
# API restarts with the new values).
#
#   scripts/make-k8s-objects.sh [--generate] [--dry-run]
#
#   namespace                       NAMESPACE (site/deploy.env)
#   Secret    optio-site-secrets    site/secrets.env, minus POSTGRES_PASSWORD, REGISTRY_*, DB_SECRET_*
#   Secret    optio-site-env        site/site.env
#   ConfigMap optio-site-ca         CA_FILE, as ca.crt
#   Secret    optio-registry        REGISTRY_* in site/secrets.env (skipped when empty)
#   SA        optio-agent           agent pods' identity: no API token, the registry pull secret
#   ConfigMap optio-config          empty, only when missing (apply-config.sh fills it)
#
#   --generate   first fill the empty (gen) keys of site/secrets.env with random hex; a filled key is
#                never changed
#   --dry-run    print the objects instead of applying them
# Needs kubectl. Refuses to change OPTIO_ENCRYPTION_KEY once the cluster has one.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

generate=0 dry=0
for a in "$@"; do
  case "$a" in
    --generate) generate=1 ;;
    --dry-run) dry=1 ;;
    *) die "unknown option $a" ;;
  esac
done
load_deploy_env
SECRETS=site/secrets.env
[ -f "$SECRETS" ] || die "$SECRETS is missing: cp site/secrets.env.example $SECRETS"
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rand_hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

if [ "$generate" = 1 ]; then
  for spec in OPTIO_ENCRYPTION_KEY:32 OPTIO_SETUP_TOKEN:16 GITLAB_WEBHOOK_SECRET:32 \
    JIRA_WEBHOOK_SECRET:32 POSTGRES_PASSWORD:24; do
    k="${spec%%:*}" n="${spec##*:}"
    if grep -qE "^$k=$" "$SECRETS"; then
      sed -i "s/^$k=$/$k=$(rand_hex "$n")/" "$SECRETS"
      note "generated $k"
    fi
  done
fi

require_filled site/site.env
[ -f "$CA_FILE" ] || die "CA_FILE $CA_FILE is missing (PEM bundle of our CA)"
grep -q "BEGIN CERTIFICATE" "$CA_FILE" || die "$CA_FILE holds no PEM certificate"

key="$(env_get "$SECRETS" OPTIO_ENCRYPTION_KEY)"
[ -n "$key" ] || die "OPTIO_ENCRYPTION_KEY is empty in $SECRETS (run with --generate)"
live="$(kube_ns get secret optio-site-secrets -o jsonpath='{.data.OPTIO_ENCRYPTION_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)"
if [ -n "$live" ] && [ "$live" != "$key" ]; then
  die "OPTIO_ENCRYPTION_KEY in $SECRETS differs from the one in the cluster. Changing it makes every stored secret unreadable. Restore the old value in $SECRETS."
fi

env_lines "$SECRETS" | grep -vE '^(POSTGRES_PASSWORD|REGISTRY_[A-Z_]+|DB_SECRET_[A-Za-z0-9_]+)=' \
  | grep -vE '^[A-Za-z0-9_]+=$' > "$tmp/site-secrets.env" || true
env_lines site/site.env > "$tmp/site-env.env"

out="$tmp/objects.yaml"
{
  kube create namespace "$NAMESPACE" --dry-run=client -o yaml
  echo "---"
  kube_ns create secret generic optio-site-secrets --from-env-file="$tmp/site-secrets.env" \
    --dry-run=client -o yaml
  echo "---"
  kube_ns create secret generic optio-site-env --from-env-file="$tmp/site-env.env" \
    --dry-run=client -o yaml
  echo "---"
  kube_ns create configmap optio-site-ca --from-file=ca.crt="$CA_FILE" --dry-run=client -o yaml
} > "$out"

reg_server="$(env_get "$SECRETS" REGISTRY_SERVER)"
reg_user="$(env_get "$SECRETS" REGISTRY_USERNAME)"
reg_pass="$(env_get "$SECRETS" REGISTRY_PASSWORD)"
pull=""
if [ -n "$reg_server" ] && [ -n "$reg_user" ] && [ -n "$reg_pass" ]; then
  auth="$(printf '%s:%s' "$reg_user" "$reg_pass" | base64 -w0)"
  printf '{"auths":{%s:{"auth":"%s"}}}' "$(json_string "$reg_server")" "$auth" > "$tmp/dockerconfig.json"
  {
    echo "---"
    kube_ns create secret generic optio-registry --type=kubernetes.io/dockerconfigjson \
      --from-file=.dockerconfigjson="$tmp/dockerconfig.json" --dry-run=client -o yaml
  } >> "$out"
  pull=$'imagePullSecrets:\n  - name: optio-registry'
fi

cat >> "$out" <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: optio-agent
  namespace: $NAMESPACE
# Agents get no Kubernetes API token (the chart's own agent account does the same).
automountServiceAccountToken: false
$pull
EOF

if [ "$dry" = 1 ]; then
  sed -E 's/^(  [A-Za-z0-9_.]+: )[A-Za-z0-9+\/=]{12,}$/\1<redacted>/' "$out"
  exit 0
fi

kube apply -f "$out"
if ! kube_ns get configmap optio-config >/dev/null 2>&1; then
  kube_ns create configmap optio-config
fi
note "done. Next: scripts/deploy.sh (it restarts the API when these values changed)"
