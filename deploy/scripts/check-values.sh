#!/usr/bin/env bash
# Report keys in a site values file that the Optio chart does not know (typos, keys from a newer
# chart). Helm ignores unknown keys silently, so a misspelled key just does nothing.
#
#   scripts/check-values.sh <chart.tgz | chart dir | values.yaml of the chart> [site values.yaml]
#
# A key is known when the chart's values.yaml has it, or when one of its parents is an empty map or
# list there ({} / []: free-form, e.g. existingSecrets, nodeSelector, annotations).
# bash + awk + tar only. Exit 1 when unknown keys are found.
set -euo pipefail

chart="${1:?usage: scripts/check-values.sh <chart.tgz|chart dir|chart values.yaml> [values.yaml]}"
site="${2:-$(dirname "${BASH_SOURCE[0]}")/../values/values.yaml}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -d "$chart" ]; then
  chart_values="$chart/values.yaml"
elif [[ "$chart" == *.tgz ]]; then
  tar -xzf "$chart" -C "$tmp" optio/values.yaml
  chart_values="$tmp/optio/values.yaml"
else
  chart_values="$chart"
fi
[ -f "$chart_values" ] || { echo "no chart values.yaml at $chart_values" >&2; exit 2; }
[ -f "$site" ] || { echo "no site values at $site" >&2; exit 2; }

# Flatten block-style YAML maps to "path<TAB>kind" (kind: map, free, leaf). List items, block scalars
# and flow maps are not descended into.
flatten() {
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    BEGIN { depth = 0; skip = -1 }
    /^[[:space:]]*(#|$)/ { next }
    {
      ind = indent($0)
      if (skip >= 0 && ind > skip) next
      skip = -1
      line = substr($0, ind + 1)
      while (depth > 0 && ind <= ind_at[depth]) depth--
      if (line ~ /^- /) { skip = ind; next }
      if (!match(line, /^("[^"]+"|[A-Za-z0-9_.\/-]+):([[:space:]]|$)/)) next
      key = substr(line, 1, RLENGTH); sub(/:[[:space:]]*$/, "", key); gsub(/"/, "", key)
      val = substr(line, RLENGTH + 1); sub(/[[:space:]]+#.*$/, "", val); gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      path = (depth ? path_at[depth] "." : "") key
      if (val == "") kind = "map"
      else if (val == "{}" || val == "[]") kind = "free"
      else kind = "leaf"
      if (val ~ /^[|>]/) skip = ind
      print path "\t" kind
      if (kind == "map") { depth++; ind_at[depth] = ind; path_at[depth] = path }
    }
  ' "$1"
}

flatten "$chart_values" > "$tmp/chart"
flatten "$site" > "$tmp/site"

declare -A chart_kind
while IFS=$'\t' read -r path kind; do chart_kind["$path"]="$kind"; done < "$tmp/chart"

unknown=0
while IFS=$'\t' read -r path _; do
  known=0
  probe="$path"
  while :; do
    if [ -n "${chart_kind[$probe]:-}" ]; then
      # The key itself, or a free-form parent ({} / [] in the chart).
      if [ "$probe" = "$path" ] || [ "${chart_kind[$probe]}" = free ]; then known=1; fi
      break
    fi
    [[ "$probe" == *.* ]] || break
    probe="${probe%.*}"
  done
  if [ "$known" = 0 ]; then
    echo "unknown key: $path"
    unknown=$((unknown + 1))
  fi
done < "$tmp/site"

if [ "$unknown" -gt 0 ]; then
  echo "$unknown key(s) the chart does not read — fix the spelling, or the chart version is older than the key." >&2
  exit 1
fi
echo "all $(wc -l < "$tmp/site") keys in $(basename "$site") are known to the chart"
