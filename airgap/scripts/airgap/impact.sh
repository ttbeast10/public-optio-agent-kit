#!/usr/bin/env bash
# AIRGAP-FORK: impact.sh — which Optio images, chart, offline kit and tests a change needs.
#
#   bash scripts/airgap/impact.sh                 uncommitted changes (staged, unstaged, untracked)
#   bash scripts/airgap/impact.sh <base>..<head>  a commit range, e.g. upstream-main..HEAD
#   bash scripts/airgap/impact.sh --files a b c   an explicit list of paths
#
# Rules mirror MANIFEST.md (change → rebuild) and the COPY lines of Dockerfile.api, Dockerfile.web and
# images/base.Dockerfile. Read-only: it never builds or deploys anything.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

files=()
RANGE="HEAD"
if [ "${1:-}" = "--files" ]; then
  shift
  files=("$@")
elif [ -n "${1:-}" ]; then
  RANGE="$1"
  while IFS= read -r f; do files+=("$f"); done < <(git diff --name-only "$1")
else
  while IFS= read -r f; do files+=("$f"); done < <(
    { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "No changed files."
  exit 0
fi

api=0 web=0 agent=0 helm=0 zarf=0 kit=0 deps_check=0 optio_img=0 tooling=0
pkgs=""      # space-separated package names whose tests to run
tests=""     # newline-separated per-file test commands
relevant=0

add_pkg() { case " $pkgs " in *" $1 "*) ;; *) pkgs="$pkgs $1" ;; esac; }

# A changed source file with a sibling test → a one-file vitest command.
add_test_for() {
  local f="$1" dir pkgjson name rel base cand
  case "$f" in apps/*/*|packages/*/*) ;; *) return 0 ;; esac
  dir="$(echo "$f" | cut -d/ -f1-2)"
  pkgjson="$dir/package.json"
  [ -f "$pkgjson" ] || return 0
  name="$(sed -n 's/^ *"name": *"\([^"]*\)".*/\1/p' "$pkgjson" | head -1)"
  rel="${f#"$dir"/}"
  case "$rel" in
    *.test.ts|*.test.tsx) cand="$rel" ;;
    *.ts|*.tsx) base="${rel%.*}"; cand=""
      for ext in test.ts test.tsx; do [ -f "$dir/$base.$ext" ] && cand="$base.$ext" && break; done ;;
    *) return 0 ;;
  esac
  [ -n "$cand" ] || return 0
  case "$cand" in
    *.int.test.ts) [ -f "$dir/vitest.integration.config.ts" ] && cand="--config vitest.integration.config.ts $cand  # needs Docker + postgres/redis" ;;
    *.e2e.test.ts) [ -f "$dir/vitest.e2e.config.ts" ] && cand="--config vitest.e2e.config.ts $cand" ;;
  esac
  tests="$tests"$'\n'"  pnpm --filter $name exec vitest run $cand"
}

for f in "${files[@]}"; do
  case "$f" in
    pnpm-lock.yaml|package.json|patches/*)
      kit=1; api=1; web=1; agent=1; relevant=1 ;;
    apps/*/package.json|packages/*/package.json)
      deps_check=1; relevant=1 ;;
    apps/android/*|apps/ios/*|apps/site/*|design/*|docs/*|*.md)
      ;;  # not deployed here
    apps/api/*)            api=1; add_pkg @optio/api; relevant=1 ;;
    apps/cli/*)            api=1; add_pkg @optio/cli; relevant=1 ;;
    apps/web/*)            web=1; add_pkg @optio/web; relevant=1 ;;
    packages/shared/*)     api=1; web=1; add_pkg @optio/shared; relevant=1 ;;
    packages/ticket-providers/*) api=1; add_pkg @optio/ticket-providers; relevant=1 ;;
    packages/agent-adapters/*)   api=1; add_pkg @optio/agent-adapters; relevant=1 ;;
    packages/container-runtime/*) api=1; add_pkg @optio/container-runtime; relevant=1 ;;
    packages/mcp-bridge/*) api=1; agent=1; add_pkg @optio/mcp-bridge; relevant=1 ;;
    images/*|Dockerfile.agent|scripts/repo-init.sh|scripts/optio-git-credential|scripts/optio-gh-wrapper|scripts/optio-glab-wrapper|scripts/check-preinstalled-mcp.mjs)
      agent=1; relevant=1 ;;
    Dockerfile.api)        api=1; relevant=1 ;;
    Dockerfile.web)        web=1; relevant=1 ;;
    Dockerfile.optio)      optio_img=1; relevant=1 ;;
    helm/*)                helm=1; relevant=1 ;;
    deploy/zarf/*)         zarf=1; relevant=1 ;;
    scripts/offline/*|scripts/airgap/*|scripts/check-agent-guides.sh|scripts/helm-value-map.sh) tooling=1; relevant=1 ;;
    *) ;;
  esac
  add_test_for "$f"
done

# Agent image list: base, dind and every preset the offline build knows.
agent_names="agent-base,agent-dind"
if [ -f scripts/offline/presets.txt ]; then
  while IFS= read -r p; do
    case "$p" in ''|'#'*) continue ;; esac
    agent_names="$agent_names,agent-$p"
  done < scripts/offline/presets.txt
fi

only=""
[ "$api" = 1 ] && only="api"
[ "$web" = 1 ] && only="${only:+$only,}web"
[ "$agent" = 1 ] && only="${only:+$only,}$agent_names"

echo "Changed files: ${#files[@]}"
[ "$relevant" = 1 ] || { echo "Nothing that ships (docs, guides or mobile/site only). No rebuild."; exit 0; }
echo

if [ "$kit" = 1 ]; then
  echo "!! Dependencies changed (package.json / pnpm-lock.yaml / patches)."
  echo "!! A NEW OFFLINE KIT is required (scripts/offline/make-kit.sh, outside), then rebuild everything."
  echo
fi
if [ "$deps_check" = 1 ]; then
  echo "?? A workspace package.json changed. If its dependencies changed, a new offline kit is required."
  echo "   Check: git diff $RANGE -- 'apps/*/package.json' 'packages/*/package.json'"
  echo
fi

if [ -n "$only" ]; then
  echo "Images to rebuild:"
  echo "  --only $only"
  [ "$agent" = 1 ] && echo "  (agent images share one Helm tag: build all of them, then recycle repo pods)"
else
  echo "Images to rebuild: none"
fi
[ "$optio_img" = 1 ] && echo "  Dockerfile.optio changed: legacy assistant image (optio.enabled, off by default)"
echo

echo "Helm:"
[ "$api" = 1 ] && echo "  --set api.image.tag=<TAG>"
[ "$web" = 1 ] && echo "  --set web.image.tag=<TAG>"
[ "$agent" = 1 ] && echo "  --set agent.image.tag=<TAG>"
[ "$helm" = 1 ] && echo "  chart changed: helm lint helm/optio --set encryption.key=test, then helm upgrade"
[ "$helm" = 1 ] && echo "  and regenerate the value map: bash scripts/helm-value-map.sh"
[ "$api$web$agent$helm" = "0000" ] && echo "  nothing"
[ "$zarf" = 1 ] && echo "Zarf: package changed → zarf package create deploy/zarf"
[ "$tooling" = 1 ] && echo "Build tooling changed (scripts/offline or scripts/airgap): nothing to deploy"
echo

echo "Tests:"
for p in $pkgs; do echo "  pnpm --filter $p typecheck"; done
ntests="$(printf '%s\n' "$tests" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
if [ "$ntests" -gt 12 ]; then
  echo "  ($ntests test files touched: run the package suites instead)"
  for p in $pkgs; do echo "  pnpm --filter $p test"; done
elif [ -n "$tests" ]; then
  printf '%s\n' "$tests" | sed '/^$/d' | sort -u
elif [ -n "$pkgs" ]; then
  for p in $pkgs; do echo "  pnpm --filter $p test"; done
fi
[ "$helm" = 1 ] && echo "  helm lint helm/optio --set encryption.key=test"
echo "  bash scripts/check-agent-guides.sh   # guides and helm/VALUES-MAP.md still match the code"
exit 0
