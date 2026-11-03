#!/usr/bin/env bash
# Shared helpers for the deploy scripts. Sourced, not run.
# Needs: bash 4+, coreutils, kubectl; helm and curl where a script says so.

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEPLOY_ROOT"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "--- $*"; }

# site/deploy.env is sourced (quoted values); the other env files are parsed, never sourced.
load_deploy_env() {
  [ -f site/deploy.env ] || die "site/deploy.env is missing: cp site/deploy.env.example site/deploy.env and fill it"
  # shellcheck source=/dev/null
  . site/deploy.env
  : "${NAMESPACE:?}" "${RELEASE:?}"
  local v
  for v in KUBE_CONTEXT NAMESPACE RELEASE OPTIO_VERSION REG_OPTIO REG_MIRROR OPTIO_SERVER; do
    [[ "${!v:-}" == *"<FILL"* ]] && die "site/deploy.env: $v still has a <FILL> placeholder"
  done
  return 0
}

kube() { kubectl --context "$KUBE_CONTEXT" "$@"; }
kube_ns() { kubectl --context "$KUBE_CONTEXT" -n "$NAMESPACE" "$@"; }

# env_keys <file>: the KEY=value lines of an env file, comments and blank lines dropped, KEY=value kept
# as written (no quote handling, no expansion).
env_lines() {
  [ -f "$1" ] || die "$1 is missing"
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" || true
}
env_get() { env_lines "$1" | grep -E "^$2=" | tail -1 | cut -d= -f2-; }

# fail on <FILL placeholders left on lines that are not comments.
require_filled() {
  local f hits
  for f in "$@"; do
    hits="$(grep -nE '^[^#]*<FILL' "$f" || true)"
    [ -z "$hits" ] || die "$f still has placeholders:"$'\n'"$hits"
  done
}

# The env names and Secret refs in values.yaml's existingSecrets block, one "ENV SECRET KEY" per line.
existing_secret_refs() {
  awk '
    /^existingSecrets:/ { on = 1; next }
    on && /^[^[:space:]#]/ { on = 0 }
    on && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\{/ {
      env = $1; sub(/:$/, "", env)
      name = $0; sub(/.*name:[[:space:]]*/, "", name); sub(/[,[:space:]}].*/, "", name)
      key = $0; sub(/.*key:[[:space:]]*/, "", key); sub(/[,[:space:]}].*/, "", key)
      print env, name, key
    }
  ' values/values.yaml
}

# api_call <METHOD> <path> [json body]: the Optio API with the API key in OPTIO_TOKEN.
api_call() {
  : "${OPTIO_TOKEN:?export OPTIO_TOKEN=<an API key from Settings → API keys>}"
  local ca=() body=()
  [ -n "${CA_FILE:-}" ] && [ -f "$CA_FILE" ] && ca=(--cacert "$CA_FILE")
  [ -n "${3:-}" ] && body=(-H "Content-Type: application/json" --data-binary "$3")
  curl -fsS "${ca[@]}" -X "$1" -H "Authorization: Bearer $OPTIO_TOKEN" "${body[@]}" "$OPTIO_SERVER$2"
}

json_string() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\t'/\\t}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"
  printf '"%s"' "$s"
}
