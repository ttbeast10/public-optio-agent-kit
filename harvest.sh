#!/usr/bin/env bash
# optio-agent-kit harvest — copy guide edits made inside an Optio checkout back into this kit.
#
#   ./harvest.sh [--dry-run] [--add-new] <optio-checkout>
#
# For every kit file, a different copy in the checkout is copied back into the layer that owns the path
# (airgap/ when the path exists there, else core/). The "Start here" section of the root AGENTS.md goes
# back to snippets/agents-md-section.md. Team-owned files (site facts, worklog) are never harvested.
#   --add-new   also take AGENTS.md / CLAUDE.md files and .claude/skills that the kit doesn't have yet
#               (AGENTS.md and shim CLAUDE.md → core/, skills → airgap/)
# Then review with `git diff` in this repo, run tests/run-tests.sh, commit.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM_FILES=" docs/airgap/site-facts.md docs/airgap/worklog.md "
START_MARK="<!-- agent-guides:start -->"
END_MARK="<!-- agent-guides:end -->"

dry=0 addnew=0 target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --add-new) addnew=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) target="$1" ;;
  esac
  shift
done
[ -n "$target" ] || { echo "usage: ./harvest.sh [--dry-run] [--add-new] <optio-checkout>" >&2; exit 2; }
target="$(cd "$target" && pwd)"

changed=0
take() {  # take <src in checkout> <dst in kit>
  echo "harvest $2"
  changed=$((changed + 1))
  [ "$dry" = 1 ] && return 0
  mkdir -p "$(dirname "$KIT/$2")"
  cp "$1" "$KIT/$2"
}

known=""
for l in core airgap; do
  while IFS= read -r f; do
    known="$known $f"
    case "$TEAM_FILES" in *" $f "*) continue ;; esac
    owner=core; [ -f "$KIT/airgap/$f" ] && owner=airgap
    [ "$l" = "$owner" ] || continue
    src="$target/$f"
    [ -f "$src" ] || { echo "missing $f (in the kit, not in the checkout)"; continue; }
    cmp -s "$src" "$KIT/$owner/$f" || take "$src" "$owner/$f"
  done < <(cd "$KIT/$l" && find . -type f | sed 's|^\./||' | sort)
done

if [ -f "$target/AGENTS.md" ] && grep -qF "$START_MARK" "$target/AGENTS.md"; then
  tmp="$(mktemp)"
  awk -v s="$START_MARK" -v e="$END_MARK" '$0 == s { on = 1 } on { print } on && $0 == e { exit }' "$target/AGENTS.md" > "$tmp"
  if cmp -s "$tmp" "$KIT/snippets/agents-md-section.md"; then rm -f "$tmp"; else take "$tmp" "snippets/agents-md-section.md"; rm -f "$tmp"; fi
fi

if [ "$addnew" = 1 ]; then
  while IFS= read -r f; do
    case " $known " in *" $f "*) continue ;; esac
    case "$f" in
      AGENTS.md|CLAUDE.md) continue ;;                 # root files are upstream's / the router
      .claude/skills/*) take "$target/$f" "airgap/$f" ;;
      *) take "$target/$f" "core/$f" ;;
    esac
  done < <(cd "$target" && { git ls-files -- '*AGENTS.md' '*CLAUDE.md' '.claude/skills/*'
                             git ls-files --others --exclude-standard -- '*AGENTS.md' '*CLAUDE.md' '.claude/skills/*'; } \
             | grep -v -E '^(apps/(android|ios|site)/|node_modules/)' | sort -u)
fi

echo "$changed file(s) harvested$([ "$dry" = 1 ] && echo ' (dry run)'). Review: git -C \"$KIT\" diff"
