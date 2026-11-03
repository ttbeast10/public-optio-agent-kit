#!/usr/bin/env bash
# Copy the deploy starter into your own deploy repo, or update it there.
#
#   deploy/init.sh [--dry-run] <deploy repo folder>
#
# Kit-owned files (scripts, skills, CLAUDE.md, README.md, site/*.example, the Dockerfile) are added or
# updated. Team-owned files (values/, config/, site/site-facts.md, .gitignore) are added only when
# missing and never overwritten. Nothing is deleted. bash + coreutils only.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_VERSION="$(cat "$SRC/../VERSION" 2>/dev/null || echo unknown)"
dry=0
[ "${1:-}" = --dry-run ] && { dry=1; shift; }
DEST="${1:?usage: deploy/init.sh [--dry-run] <deploy repo folder>}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"

team_owned() {
  case "$1" in
    values/* | config/* | site/site-facts.md | .gitignore) return 0 ;;
    *) return 1 ;;
  esac
}

added=0 updated=0 same=0 kept=0
while IFS= read -r -d '' f; do
  rel="${f#"$SRC"/}"
  [ "$rel" = init.sh ] && continue
  dst="$DEST/$rel"
  if [ -e "$dst" ]; then
    if team_owned "$rel"; then
      kept=$((kept + 1)); continue
    fi
    if cmp -s "$f" "$dst"; then
      same=$((same + 1)); continue
    fi
    echo "update  $rel"; updated=$((updated + 1))
  else
    echo "add     $rel"; added=$((added + 1))
  fi
  if [ "$dry" = 0 ]; then
    mkdir -p "$(dirname "$dst")"
    cp -p "$f" "$dst"
  fi
done < <(find "$SRC" -type f -print0 | sort -z)

[ "$dry" = 0 ] && echo "optio-agent-kit $KIT_VERSION deploy starter" > "$DEST/.optio-deploy-kit"
echo "deploy starter $KIT_VERSION: $added added, $updated updated, $same unchanged, $kept team-owned kept.$([ "$dry" = 1 ] && echo ' (dry run)')"
[ "$dry" = 1 ] || echo "Next: README.md, phase 0. Agents: CLAUDE.md and .claude/skills/."
