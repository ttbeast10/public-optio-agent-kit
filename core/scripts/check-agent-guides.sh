#!/usr/bin/env bash
# Check the agent guides (nested AGENTS.md / CLAUDE.md files, docs/agent-guides, .claude/skills,
# .claude/agents, plus any file or folder listed in an optional .agent-guides file) against the tree:
#
#   bash scripts/check-agent-guides.sh
#
# 1. Every path written in inline code must exist: relative to the repo root, to the guide's own folder,
#    or — for a bare file name — anywhere in the repo. Code blocks, globs (*), placeholders (<…>), URLs,
#    absolute paths and package names (@optio/…) are skipped. The root AGENTS.md is not checked (it is the
#    long-form reference and uses paths relative to several folders).
# 2. Every `@path` import line in a CLAUDE.md must resolve.
# 3. Fails when helm/VALUES-MAP.md is out of date with the chart (scripts/helm-value-map.sh --check).
# 4. Lists service modules that apps/api/src/services/AGENTS.md does not mention (info only).
# Exit code 1 when a path or an import is missing, or the value map is stale. Needs only bash, git, awk, grep, sed, find.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# Names that live outside the repo and are fine to mention.
EXTERNAL=" KIT.md DROP.md SHA256SUMS optio.bundle .claude/settings.local.json jira.js "

BASENAMES="$(git ls-files 2>/dev/null | sed 's#.*/##' | sort -u || true)"

guides=()
while IFS= read -r g; do guides+=("$g"); done < <(
  { find . \( -name AGENTS.md -o -name CLAUDE.md \) \
      -not -path '*/node_modules/*' -not -path './.git/*' -not -path './AGENTS.md'
    find docs/agent-guides .claude/skills .claude/agents -name '*.md' 2>/dev/null || true
    if [ -f .agent-guides ]; then
      while IFS= read -r extra; do
        case "$extra" in ''|'#'*) continue ;; esac
        [ -e "$extra" ] && find "$extra" -name '*.md'
      done < .agent-guides
    fi
  } | sed 's|^\./||' | sort -u)

missing=0
checked=0
for g in "${guides[@]}"; do
  gdir="$(dirname "$g")"

  # @imports (CLAUDE.md files only), outside code blocks
  case "$g" in
    *CLAUDE.md)
      while IFS= read -r imp; do
        p="${imp#@}"
        if [ ! -e "$gdir/$p" ]; then
          echo "MISSING IMPORT  $g  →  @$p"
          missing=$((missing + 1))
        fi
      done < <(awk '/^[ \t]*```/ { f = !f; next } !f && /^@[^ ]+$/ { print }' "$g")
      ;;
  esac

  while IFS= read -r tok; do
    t="${tok%%:[0-9]*}"          # drop :line suffix
    t="${t%/}"                   # drop trailing slash
    case "$t" in
      ''|*' '*|*'<'*|*'>'*|*'*'*|*'{'*|*'$'*|*'='*|*'|'*|*'://'*|/*|@*|-*|'~'*) continue ;;
    esac
    case " $EXTERNAL " in *" $t "*) continue ;; esac
    looks_like_path=0
    case "$t" in */*) looks_like_path=1 ;; esac
    case "$t" in *.ts|*.tsx|*.js|*.mjs|*.md|*.sh|*.yaml|*.yml|*.json|*.txt|*.sql|*Dockerfile|*Dockerfile.*|*.Dockerfile) looks_like_path=1 ;; esac
    [ "$looks_like_path" = 1 ] || continue
    case "$t" in */*) ;; .*) continue ;; esac   # `.ts`, `.mcp.json`: extensions, generated dotfiles
    checked=$((checked + 1))
    if [ -e "$t" ] || [ -e "$gdir/$t" ]; then continue; fi
    case "$t" in
      */*) ;;
      *) if grep -qxF -- "$t" <<< "$BASENAMES"; then continue; fi ;;
    esac
    echo "MISSING  $g  →  $tok"
    missing=$((missing + 1))
  done < <(awk '
    /^[ \t]*```/ { fence = !fence; next }
    !fence {
      line = $0
      while (match(line, /`[^`]+`/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$g")
done

# The generated Helm value map must match the chart and code it was made from.
if [ -f scripts/helm-value-map.sh ] && [ -f helm/optio/values.yaml ]; then
  if ! bash scripts/helm-value-map.sh --check; then missing=$((missing + 1)); fi
fi

echo "Agent guides: ${#guides[@]} files, $checked path references checked, $missing missing."

idx="apps/api/src/services/AGENTS.md"
if [ -f "$idx" ]; then
  globs="$(grep -o '`[a-z0-9-]*\*\.ts`' "$idx" | tr -d '`' | sort -u || true)"
  unindexed=""
  for f in apps/api/src/services/*.ts; do
    b="$(basename "$f")"
    case "$b" in *.test.ts) continue ;; esac
    grep -q "\`$b\`" "$idx" && continue
    hit=0
    for gl in $globs; do
      # shellcheck disable=SC2254
      case "$b" in $gl) hit=1; break ;; esac
    done
    [ "$hit" = 1 ] || unindexed="$unindexed ${b%.ts}"
  done
  [ -z "$unindexed" ] || echo "INFO  service modules not in $idx:$unindexed"
fi


[ "$missing" -eq 0 ]
