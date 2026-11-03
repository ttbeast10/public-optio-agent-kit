#!/usr/bin/env bash
# Publish config/ (configuration as code) as the ConfigMap optio-config, which the API mounts and
# re-reads every configAsCode.intervalMs. The files are the truth: what changes is applied, what
# disappears is pruned, UI edits to managed resources are put back.
#
#   scripts/apply-config.sh [--diff] [--sync] [--dry-run]
#
#   --diff     first show what would change, with the Optio CLI (`optio diff`), when it is installed:
#              curl -fsSLO "$OPTIO_SERVER/api/cli/optio-cli.tgz" (needs Node on this machine)
#   --sync     after publishing, wait for the mount to update and run a sync now; print its summary
#   --dry-run  run the checks and print the ConfigMap; change nothing
# Checks: config/ is flat (a ConfigMap has no folders), no <FILL> left, every *File a manifest names
# exists next to it, every YAML document has apiVersion optio/v1, the total stays under 900 KiB.
# Needs kubectl; curl for --sync. OPTIO_TOKEN (an API key) for --diff and --sync.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

diff=0 sync=0 dry=0
for a in "$@"; do
  case "$a" in
    --diff) diff=1 ;;
    --sync) sync=1 ;;
    --dry-run) dry=1 ;;
    *) die "unknown option $a" ;;
  esac
done
load_deploy_env
DIR=config
[ -d "$DIR" ] || die "no $DIR/ directory"

note "checks"
sub="$(find "$DIR" -mindepth 1 -type d | head -1)"
[ -z "$sub" ] || die "$sub: config/ must be flat (ConfigMap keys can't hold folders); use name prefixes like work-*.yaml"
shopt -s nullglob
files=("$DIR"/*)
[ "${#files[@]}" -gt 0 ] || die "$DIR/ is empty"
require_filled "${files[@]}"
for f in "$DIR"/*.yaml "$DIR"/*.yml; do
  docs="$(grep -cE '^kind:' "$f" || true)"
  versions="$(grep -cE '^apiVersion:[[:space:]]*optio/v1[[:space:]]*$' "$f" || true)"
  [ "$docs" -gt 0 ] || die "$f has no kind:"
  [ "$docs" = "$versions" ] || die "$f: every document needs apiVersion: optio/v1"
  grep -qE '^[[:space:]]+filesFrom:' "$f" && die "$f: filesFrom names a folder, which a ConfigMap can't hold; use promptFile"
  while read -r ref; do
    [ -n "$ref" ] || continue
    [[ "$ref" == */* ]] && die "$f names $ref: keep referenced files next to the manifest, no folders"
    [ -f "$DIR/$ref" ] || die "$f names $ref, which is not in $DIR/"
  done < <(sed -nE 's/^[[:space:]]+(promptFile|templateFile|systemPromptFile|agentsMdFile):[[:space:]]*"?([^"#[:space:]]+)"?.*/\2/p' "$f")
done
size="$(cat "${files[@]}" | wc -c)"
[ "$size" -lt 921600 ] || die "config/ is $size bytes; a ConfigMap holds 1 MiB. Split prompts or move to a volume (README)."
note "${#files[@]} files, $size bytes"

if [ "$diff" = 1 ]; then
  if command -v optio >/dev/null; then
    OPTIO_SERVER="$OPTIO_SERVER" OPTIO_TOKEN="${OPTIO_TOKEN:?export OPTIO_TOKEN}" optio diff -f "$DIR"
  else
    echo "optio CLI not installed; skipping --diff (Settings → Config as code → Preview shows the same after publishing)"
  fi
fi

cm="$(kube_ns create configmap optio-config --from-file="$DIR" --dry-run=client -o yaml)"
if [ "$dry" = 1 ]; then
  echo "$cm"
  exit 0
fi
echo "$cm" | kube apply -f -
note "published ConfigMap optio-config; the API picks it up within about two minutes"

if [ "$sync" = 1 ]; then
  note "waiting 90 s for the volume to update, then syncing"
  sleep 90
  api_call POST /api/config/source/sync | grep -oE '"summary":\{[^}]*\}' || true
  echo
  echo "Errors, if any: Settings → Config as code, or GET $OPTIO_SERVER/api/config/status"
fi
