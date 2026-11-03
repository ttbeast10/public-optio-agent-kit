#!/usr/bin/env bash
# Self-test for optio-agent-kit. Offline; leaves the given checkout untouched (works on throwaway clones).
#
#   tests/run-tests.sh /path/to/optio
#
# Optional: PRETTIER=/path/to/prettier also checks Markdown formatting (Optio's pre-commit hook does).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "${1:-}" ] || { echo "usage: tests/run-tests.sh /path/to/optio" >&2; exit 2; }
SRC="$(cd "$1" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0 fail=0
ok() { echo "ok    $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; fail=$((fail + 1)); }
t() { local d="$1"; shift; if "$@" >"$T/last.log" 2>&1; then ok "$d"; else bad "$d"; sed 's/^/      /' "$T/last.log" | tail -15; fi; }
clone() {
  git clone -q "$SRC" "$T/$1"
  git -C "$T/$1" config user.email kit-test@localhost
  git -C "$T/$1" config user.name "kit test"
}
contains() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }

echo "== syntax"
for s in "$KIT"/*.sh "$KIT"/tests/*.sh "$KIT"/core/scripts/*.sh "$KIT"/airgap/scripts/airgap/*.sh $(ls "$KIT"/tools/*.sh 2>/dev/null); do
  t "bash -n $(basename "$s")" bash -n "$s"
done

echo "== core layer is generic (no fork or site content)"
t "core has no fork markers or site facts" bash -c \
  "! grep -rnE 'AIRGAP-FORK|<FILL|docs/airgap|scripts/airgap|Deep[S]eek|LiteLLM|site-facts|worklog|\bD[O]K\b' '$KIT/core' '$KIT/snippets'"

echo "== guide size budget (≤ 130 lines)"
while IFS= read -r g; do
  t "size $(realpath --relative-to="$KIT" "$g")" test "$(wc -l < "$g")" -le 130
done < <(find "$KIT/core" "$KIT/airgap" -name AGENTS.md -o -name CLAUDE.md -path "$KIT/airgap/CLAUDE.md")

echo "== install core"
clone c1
t "install --layer core" "$KIT/install.sh" --layer core "$T/c1"
t "check-agent-guides passes" bash -c "cd '$T/c1' && bash scripts/check-agent-guides.sh"
t "root CLAUDE.md untouched" git -C "$T/c1" diff --quiet -- CLAUDE.md
t "Start here section once" test "$(grep -cF '<!-- agent-guides:start -->' "$T/c1/AGENTS.md")" -eq 1
t "no airgap files" test ! -e "$T/c1/docs/airgap" -a ! -e "$T/c1/.claude"
"$KIT/install.sh" --layer core --no-check "$T/c1" > "$T/re.log"
t "re-install is a no-op" contains "$T/re.log" "0 added, 0 updated"

echo "== install all"
clone c2
t "install (all)" "$KIT/install.sh" "$T/c2"
t "root CLAUDE.md is the router" contains "$T/c2/CLAUDE.md" "@docs/airgap/site-facts.md"
t ".gitignore tracks skills" bash -c "! git -C '$T/c2' check-ignore -q .claude/skills/optio-debug-gitlab/SKILL.md"
t ".gitignore keeps personal settings ignored" git -C "$T/c2" check-ignore -q .claude/settings.local.json
t "impact.sh executable" test -x "$T/c2/scripts/airgap/impact.sh"
echo "| Registry (\`REG\`) | registry.test/optio |" >> "$T/c2/docs/airgap/site-facts.md"
echo "- 2026-11-03 · test · team edit" >> "$T/c2/docs/airgap/worklog.md"
"$KIT/install.sh" --no-check "$T/c2" > "$T/re2.log"
t "team-owned site facts kept" contains "$T/c2/docs/airgap/site-facts.md" "registry.test/optio"
t "team-owned worklog kept" contains "$T/c2/docs/airgap/worklog.md" "team edit"
t "re-install all is a no-op" contains "$T/re2.log" "0 added, 0 updated"
t "upgrade core → all" "$KIT/install.sh" "$T/c1"

echo "== dry run"
clone c3
"$KIT/install.sh" --dry-run "$T/c3" > /dev/null
t "dry run changes nothing" bash -c "[ -z \"\$(git -C '$T/c3' status --porcelain)\" ]"

echo "== impact.sh"
I="$T/c2/scripts/airgap/impact.sh"
(cd "$T/c2" && bash "$I" --files apps/api/src/services/git-platform/gitlab.ts) > "$T/i1.log"
t "api change → --only api" contains "$T/i1.log" "--only api"
t "api change → its test file" contains "$T/i1.log" "vitest run src/services/git-platform/gitlab.test.ts"
(cd "$T/c2" && bash "$I" --files images/base.Dockerfile) > "$T/i2.log"
t "agent image change → all agent images" contains "$T/i2.log" "agent-base,agent-dind,agent-node"
(cd "$T/c2" && bash "$I" --files pnpm-lock.yaml) > "$T/i3.log"
t "lockfile → new offline kit" contains "$T/i3.log" "NEW OFFLINE KIT"
(cd "$T/c2" && bash "$I" --files docs/tasks.md) > "$T/i4.log"
t "docs only → no rebuild" contains "$T/i4.log" "No rebuild"

echo "== helm value map"
GEN="$KIT/core/scripts/helm-value-map.sh"
t "install wrote helm/VALUES-MAP.md (core)" test -s "$T/c1/helm/VALUES-MAP.md"
t "install wrote helm/VALUES-MAP.md (all)" test -s "$T/c2/helm/VALUES-MAP.md"
(cd "$T/c3" && bash "$GEN" --stdout) > "$T/m1.md"; (cd "$T/c3" && bash "$GEN" --stdout) > "$T/m2.md"
t "map is deterministic" cmp -s "$T/m1.md" "$T/m2.md"
t "value → env → reader row" bash -c "grep -F '| \`agent.image.prefix\` |' '$T/m1.md' | grep -qF 'OPTIO_AGENT_IMAGE_PREFIX'"
t "with \$var.field resolved (auth.oidc.issuerUrl → OIDC_ISSUER_URL)" bash -c "grep -F '| \`auth.oidc.issuerUrl\` |' '$T/m1.md' | grep -qF 'OIDC_ISSUER_URL'"
t "never-set list has GITLAB_HOSTS" bash -c "sed -n '/never sets/,/no template uses/p' '$T/m1.md' | grep -qF '\`GITLAB_HOSTS\`'"
t "chart-set env not in never-set list" bash -c "! sed -n '/never sets/,/no template uses/p' '$T/m1.md' | grep -qF '\`OPTIO_OUTBOUND_ALLOWED_HOSTS\`'"
"$KIT/install.sh" --layer core --no-check "$T/c3" > /dev/null
printf 'zzzKitTest: 1\n' >> "$T/c3/helm/optio/values.yaml"
t "stale map fails the guide check" bash -c "! (cd '$T/c3' && bash scripts/check-agent-guides.sh) > '$T/stale.log' 2>&1"
t "stale message names the fix" contains "$T/stale.log" "bash scripts/helm-value-map.sh"
(cd "$T/c3" && bash scripts/helm-value-map.sh) > /dev/null
t "regenerated map passes" bash -c "cd '$T/c3' && bash scripts/check-agent-guides.sh"
t "new unused key listed" contains "$T/c3/helm/VALUES-MAP.md" "- \`zzzKitTest\`"

echo "== make-pr (upstream, core)"
clone c4
t "make-pr --layer core" "$KIT/make-pr.sh" --layer core --no-verify --out "$T/p-core" "$T/c4"
t "one patch" test "$(ls "$T/p-core" | wc -l)" -eq 1
t "conventional subject" bash -c "git -C '$T/c4' log -1 --format=%s | grep -q '^docs(agents): '"
t "core PR has no airgap files" bash -c "! git -C '$T/c4' show --stat HEAD | grep -qE 'docs/airgap|\.claude/|scripts/airgap'"
t "core PR includes the value map" bash -c "git -C '$T/c4' show --name-only --format= HEAD | grep -qx 'helm/VALUES-MAP.md'"
clone c5
t "git am applies the core patch" git -C "$T/c5" am -q "$T"/p-core/*.patch
t "check passes after git am" bash -c "cd '$T/c5' && bash scripts/check-agent-guides.sh"

echo "== make-pr (fork, all)"
clone c6
t "make-pr --layer all" "$KIT/make-pr.sh" --layer all --no-verify --out "$T/p-all" "$T/c6"
t "fork MR includes skills" bash -c "git -C '$T/c6' show --stat HEAD | grep -q '.claude/skills/optio-debug-gitlab'"
clone c7
t "git am applies the fork patch" git -C "$T/c7" am -q "$T"/p-all/*.patch
t "check passes after fork git am" bash -c "cd '$T/c7' && bash scripts/check-agent-guides.sh"

echo "== harvest"
cp -r "$KIT" "$T/kit"
echo "- harvested core line" >> "$T/c2/apps/api/AGENTS.md"
echo "- harvested airgap line" >> "$T/c2/apps/api/CLAUDE.md"
t "harvest runs" "$T/kit/harvest.sh" "$T/c2"
t "core edit lands in core/" contains "$T/kit/core/apps/api/AGENTS.md" "harvested core line"
t "airgap edit lands in airgap/" contains "$T/kit/airgap/apps/api/CLAUDE.md" "harvested airgap line"
t "team files not harvested" lacks "$T/kit/airgap/docs/airgap/site-facts.md" "registry.test/optio"

echo "== prune"
cp -r "$KIT" "$T/kit2"
rm "$T/kit2/airgap/docs/airgap/later-outside-claude.md"
"$T/kit2/install.sh" --no-check "$T/c2" > "$T/pr1.log"
t "dropped file reported as stale" contains "$T/pr1.log" "stale   docs/airgap/later-outside-claude.md"
"$T/kit2/install.sh" --no-check --prune "$T/c2" > /dev/null
t "--prune removes it" test ! -e "$T/c2/docs/airgap/later-outside-claude.md"

if [ -x "$KIT/tools/export-public.sh" ]; then
  echo "== public export"
  t "export runs" "$KIT/tools/export-public.sh" "$T/pub"
  t "no private words left" bash -c "! grep -rniE '\\bd[o]k\\b|deep ?s[e]ek' '$T/pub'"
  t "tools/ not exported" test ! -e "$T/pub/tools"
  t "private README notes dropped" lacks "$T/pub/README.md" "private:start"
  t "private CHANGELOG notes dropped" lacks "$T/pub/CHANGELOG.md" "export-public"
  t "same file count minus tools/" test "$(cd "$T/pub" && find . -type f | wc -l)" -eq "$(cd "$KIT" && git ls-files --cached --others --exclude-standard | grep -vc '^tools/')"
  clone c8
  t "exported kit installs and checks" "$T/pub/install.sh" "$T/c8"
fi

if [ -n "${PRETTIER:-}" ]; then
  echo "== prettier"
  t "markdown is prettier-formatted" bash -c "cd '$T/c7' && '$PRETTIER' --check \$(git -C '$T/c7' show --name-only --format= HEAD | grep '\.md$' | grep -v '^helm/')"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
