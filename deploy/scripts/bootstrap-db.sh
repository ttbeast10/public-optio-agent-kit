#!/usr/bin/env bash
# Store the database-only secrets through the Optio API: every DB_SECRET_<NAME>=value in
# site/secrets.env becomes the organization-wide (global) secret <NAME>. Safe to re-run: a secret is
# replaced, its id kept. Empty values are skipped. Then prints the steps only a person can do in the UI.
#
#   export OPTIO_TOKEN=<API key>     # Settings → API keys, made by a deployment admin
#   scripts/bootstrap-db.sh [--list]
#
#   --list   show the names the API has, and nothing else
# Needs curl. Run it after the first sign-in (which makes the organization's workspace) and before
# apply-config.sh: manifests that name a secret fail until it exists.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_deploy_env
if [ "${1:-}" = --list ]; then
  api_call GET /api/secrets | grep -oE '"name":"[^"]+"' | cut -d'"' -f4 | sort -u
  exit 0
fi

n=0
while IFS= read -r line; do
  name="${line%%=*}"; name="${name#DB_SECRET_}"
  value="${line#*=}"
  [ -n "$value" ] || { echo "skip  $name (empty)"; continue; }
  body="{\"name\":$(json_string "$name"),\"value\":$(json_string "$value"),\"scope\":\"global\"}"
  if api_call POST /api/secrets "$body" >/dev/null; then
    echo "set   $name"
    n=$((n + 1))
  else
    die "storing $name failed (is the key a deployment admin's? is the API reachable?)"
  fi
done < <(env_lines site/secrets.env | grep -E '^DB_SECRET_')
note "$n secret(s) stored"

cat <<'EOF'

Only in the UI (once; they are not configuration as code):
  1. Settings → Sign-in: check the provider you configured; add more admins if needed.
  2. Settings → Access: workspace creation, onboarding (an app setting here overrides Helm).
  3. Workspaces and members: invite the team, set roles.
  4. A ticket provider (Settings), only if you use `when: ticket` with GitLab issues.
  5. A webhook trigger's own secret (`when: webhook`) is minted on creation: copy it once.
  6. Claude Code may report the gateway key as unverified (the check calls the vendor). Expected.
Then: scripts/apply-config.sh --sync
EOF
