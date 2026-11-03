#!/usr/bin/env bash
# Install or upgrade the Optio release from the carried-in chart and values/values.yaml.
#
#   scripts/deploy.sh [--dry-run] [--no-backup]
#
# Before helm runs it checks: no <FILL> left, every values key known to this chart
# (check-values.sh), every existingSecrets key present in its Secret, the CA and config ConfigMaps
# and the agent ServiceAccount exist. On an upgrade it takes a pre-upgrade database dump first
# (bundle/backup/backup-db.sh when carried in, else a Job from the backup CronJob). After helm it
# restarts the API when the site Secrets / CA changed since the last deploy (the chart can't see them).
#
#   --dry-run    run the checks and `helm upgrade --dry-run`, change nothing
#   --no-backup  skip the pre-upgrade dump (only when the database holds nothing worth keeping)
# Needs kubectl and helm 3.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

dry=0 backup=1
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --no-backup) backup=0 ;;
    *) die "unknown option $a" ;;
  esac
done
load_deploy_env
umask 077
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

note "checks"
[ -f "$CHART" ] || die "chart $CHART not found (bundle/load.sh puts it there)"
require_filled values/values.yaml
bash scripts/check-values.sh "$CHART" values/values.yaml
kube get namespace "$NAMESPACE" >/dev/null || die "namespace $NAMESPACE missing: run scripts/make-k8s-objects.sh"

while read -r env name key; do
  [ -n "$env" ] || continue
  kube_ns get secret "$name" -o jsonpath="{.data.$key}" 2>/dev/null | grep -q . \
    || die "existingSecrets.$env: Secret $name has no key $key (fill site/*.env and run make-k8s-objects.sh, or remove the line)"
done < <(existing_secret_refs)

for cm in optio-site-ca optio-config; do
  kube_ns get configmap "$cm" >/dev/null 2>&1 || die "ConfigMap $cm missing: run scripts/make-k8s-objects.sh"
done
if grep -qE '^[[:space:]]+name: optio-agent' values/values.yaml; then
  kube_ns get serviceaccount optio-agent >/dev/null 2>&1 || die "ServiceAccount optio-agent missing: run scripts/make-k8s-objects.sh"
fi

pg="$(env_get site/secrets.env POSTGRES_PASSWORD)"
[ -n "$pg" ] || die "POSTGRES_PASSWORD is empty in site/secrets.env (make-k8s-objects.sh --generate)"
[[ "$pg" =~ ^[A-Za-z0-9]+$ ]] || die "POSTGRES_PASSWORD must be letters and digits only"
printf 'postgresql:\n  auth:\n    password: "%s"\n' "$pg" > "$tmp/pg.yaml"

installed=0
helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" status "$RELEASE" >/dev/null 2>&1 && installed=1

if [ "$dry" = 1 ]; then
  helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" upgrade --install "$RELEASE" "$CHART" \
    -f values/values.yaml -f "$tmp/pg.yaml" --dry-run > "$tmp/render.txt"
  note "dry run ok: $(grep -c '^kind:' "$tmp/render.txt") objects rendered; nothing changed"
  exit 0
fi

if [ "$installed" = 1 ] && [ "$backup" = 1 ]; then
  note "pre-upgrade database dump"
  if [ -x bundle/backup/backup-db.sh ]; then
    bundle/backup/backup-db.sh --namespace "$NAMESPACE" --release "$RELEASE" \
      --context "$KUBE_CONTEXT" --reason pre-upgrade
  elif kube_ns get cronjob "$RELEASE-backup" >/dev/null 2>&1; then
    job="$RELEASE-backup-pre-$(date -u +%Y%m%d%H%M%S)"
    kube_ns create job "$job" --from="cronjob/$RELEASE-backup"
    kube_ns wait --for=condition=complete "job/$job" --timeout=3600s \
      || die "pre-upgrade dump failed: kubectl -n $NAMESPACE logs job/$job"
  else
    die "no backup CronJob ($RELEASE-backup): enable backup in values, or pass --no-backup"
  fi
fi

note "helm upgrade --install $RELEASE $CHART"
helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" upgrade --install "$RELEASE" "$CHART" \
  -f values/values.yaml -f "$tmp/pg.yaml" --wait --timeout 20m

# The chart restarts the API when its own config Secret changes, not ours.
site_hash="$(for o in secret/optio-site-secrets secret/optio-site-env configmap/optio-site-ca; do
  kube_ns get "$o" -o jsonpath='{.data}'
done | sha256sum | cut -c1-16)"
last="$(kube_ns get deploy "$RELEASE-api" -o jsonpath='{.metadata.annotations.optio-site/hash}' 2>/dev/null || true)"
if [ "$site_hash" != "$last" ]; then
  if [ -n "$last" ]; then
    note "site Secrets / CA changed: restarting the API"
    kube_ns rollout restart "deploy/$RELEASE-api"
    kube_ns rollout status "deploy/$RELEASE-api" --timeout=15m
  fi
  kube_ns annotate deploy "$RELEASE-api" "optio-site/hash=$site_hash" --overwrite >/dev/null
fi
note "deployed. Next: scripts/verify.sh"
