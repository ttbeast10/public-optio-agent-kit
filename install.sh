#!/usr/bin/env bash
# optio-agent-kit installer — copies the agent guides into an Optio checkout. Offline; bash + git only.
#
#   ./install.sh [options] <optio-checkout>
#
#   --layer core     generic guides only (upstream-able): nested AGENTS.md + CLAUDE.md shims,
#                    docs/agent-guides/, scripts/check-agent-guides.sh, a "Start here" section in AGENTS.md
#   --layer all      core + airgap (default): root CLAUDE.md router, skills, scout agent, settings,
#                    docs/airgap/, scripts/airgap/, air-gap notes in some folder CLAUDE.md files
#   --dry-run        print what would change, change nothing
#   --prune          remove files a previous install added that this kit version no longer has
#   --no-check       skip scripts/check-agent-guides.sh at the end
#
# Team-owned files (docs/airgap/site-facts.md, docs/airgap/worklog.md) are installed only when missing.
# Re-running is safe: unchanged files are left alone. The install record lives in .git/ (never committed).
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_VERSION="$(cat "$KIT/VERSION")"
OPTIO_BASE="$(cat "$KIT/OPTIO_BASE")"
TEAM_FILES=" docs/airgap/site-facts.md docs/airgap/worklog.md "
START_MARK="<!-- agent-guides:start -->"
END_MARK="<!-- agent-guides:end -->"

layer=all dry=0 prune=0 check=1 target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --layer) layer="${2:?--layer needs core or all}"; shift ;;
    --layer=*) layer="${1#*=}" ;;
    --dry-run) dry=1 ;;
    --prune) prune=1 ;;
    --no-check) check=0 ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) target="$1" ;;
  esac
  shift
done
case "$layer" in core|all) ;; *) echo "--layer must be core or all" >&2; exit 2 ;; esac
[ -n "$target" ] || { echo "usage: ./install.sh [--layer core|all] [--dry-run] [--prune] <optio-checkout>" >&2; exit 2; }
target="$(cd "$target" && pwd)"
[ -f "$target/pnpm-workspace.yaml" ] && [ -d "$target/apps/api" ] || { echo "$target does not look like an Optio checkout" >&2; exit 2; }
git -C "$target" rev-parse --git-dir >/dev/null 2>&1 || { echo "$target is not a git checkout" >&2; exit 2; }

if ! git -C "$target" merge-base --is-ancestor "$OPTIO_BASE" HEAD 2>/dev/null; then
  echo "note: guides were checked against upstream ${OPTIO_BASE:0:8}, which is not in this checkout's history."
  echo "      They still install; run scripts/check-agent-guides.sh and fix what it reports (skill optio-refresh-guides)."
fi

layers="core"; [ "$layer" = all ] && layers="core airgap"

# The file list: later layers override earlier ones for the same path.
files=""
for l in $layers; do
  while IFS= read -r f; do
    case " $files " in *" $f "*) ;; *) files="$files $f" ;; esac
  done < <(cd "$KIT/$l" && find . -type f | sed 's|^\./||' | sort)
done
source_of() { local f="$1" l src=""; for l in $layers; do [ -f "$KIT/$l/$f" ] && src="$KIT/$l/$f"; done; echo "$src"; }

added=0 updated=0 same=0 kept=0
do_copy() {
  local src="$1" dst="$2"
  [ "$dry" = 1 ] && return 0
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  case "$dst" in *.sh) chmod +x "$dst" ;; esac
}
for f in $files; do
  src="$(source_of "$f")"; dst="$target/$f"
  if [ -e "$dst" ]; then
    case "$TEAM_FILES" in *" $f "*) kept=$((kept + 1)); echo "keep    $f (team-owned)"; continue ;; esac
    if cmp -s "$src" "$dst"; then same=$((same + 1)); continue; fi
    echo "update  $f"; updated=$((updated + 1)); do_copy "$src" "$dst"
  else
    echo "add     $f"; added=$((added + 1)); do_copy "$src" "$dst"
  fi
done

# Generated: helm/VALUES-MAP.md, made from this checkout's chart and code (so it matches any fork).
MAP="helm/VALUES-MAP.md"
if [ -f "$target/helm/optio/values.yaml" ]; then
  tmpmap="$(mktemp)"
  (cd "$target" && bash "$KIT/core/scripts/helm-value-map.sh" --stdout) > "$tmpmap"
  if [ ! -e "$target/$MAP" ]; then echo "add     $MAP (generated)"; added=$((added + 1)); do_copy "$tmpmap" "$target/$MAP"
  elif cmp -s "$tmpmap" "$target/$MAP"; then same=$((same + 1))
  else echo "update  $MAP (generated)"; updated=$((updated + 1)); do_copy "$tmpmap" "$target/$MAP"; fi
  rm -f "$tmpmap"
  files="$files $MAP"
fi

# "Start here" section in the root AGENTS.md (between markers; replaced on every install).
agents="$target/AGENTS.md"
if [ -f "$agents" ]; then
  tmp="$(mktemp)"
  if grep -qF "$START_MARK" "$agents"; then
    awk -v s="$START_MARK" -v e="$END_MARK" -v snip="$KIT/snippets/agents-md-section.md" '
      $0 == s { while ((getline l < snip) > 0) print l; skip = 1; next }
      skip && $0 == e { skip = 0; next }
      !skip { print }' "$agents" > "$tmp"
  else
    awk -v snip="$KIT/snippets/agents-md-section.md" '
      { print }
      !done && NR > 1 && $0 != "" && $0 !~ /^#/ { print ""; while ((getline l < snip) > 0) print l; done = 1 }' "$agents" > "$tmp"
  fi
  if cmp -s "$tmp" "$agents"; then rm -f "$tmp"
  else echo "update  AGENTS.md (Start here section)"; updated=$((updated + 1))
    if [ "$dry" = 1 ]; then rm -f "$tmp"; else cat "$tmp" > "$agents"; rm -f "$tmp"; fi
  fi
else
  echo "note: no root AGENTS.md — skipped the Start here section"
fi

# .gitignore: upstream ignores all of .claude/; track the shared parts, keep personal settings ignored.
if [ "$layer" = all ]; then
  gi="$target/.gitignore"
  if [ -f "$gi" ] && grep -qx '\.claude/' "$gi" && ! grep -qF '# optio-agent-kit: .claude' "$gi"; then
    echo "update  .gitignore (track .claude/settings.json, agents/, skills/)"; updated=$((updated + 1))
    if [ "$dry" = 0 ]; then
      tmp="$(mktemp)"
      awk '$0 == ".claude/" {
             print "# optio-agent-kit: .claude — track shared Claude Code config, keep personal settings ignored"
             print ".claude/*"; print "!.claude/settings.json"; print "!.claude/settings.local.example.json"
             print "!.claude/agents/"; print "!.claude/skills/"; next }
           { print }' "$gi" > "$tmp" && cat "$tmp" > "$gi" && rm -f "$tmp"
    fi
  fi
fi

# Install record (in .git/, never committed) and pruning of files a previous kit added.
record="$(git -C "$target" rev-parse --absolute-git-dir)/optio-agent-kit.installed"
stale=""
if [ -f "$record" ]; then
  while IFS= read -r old; do
    case "$old" in '#'*|'') continue ;; esac
    case " $files " in *" $old "*) continue ;; esac
    case "$TEAM_FILES" in *" $old "*) continue ;; esac
    [ -e "$target/$old" ] || continue
    if [ "$prune" = 1 ]; then
      echo "remove  $old (no longer in the kit)"; [ "$dry" = 1 ] || rm -f "$target/$old"
    else
      echo "stale   $old (no longer in the kit; --prune removes it)"
      stale="$stale $old"
    fi
  done < "$record"
fi
if [ "$dry" = 0 ]; then
  { echo "# optio-agent-kit $KIT_VERSION, layer $layer, upstream base $OPTIO_BASE, $(date -u +%Y-%m-%dT%H:%MZ)"
    for f in $files $stale; do echo "$f"; done; } > "$record"
fi

echo "optio-agent-kit $KIT_VERSION ($layer): $added added, $updated updated, $same unchanged, $kept team-owned kept.$([ "$dry" = 1 ] && echo ' (dry run)')"

if [ "$check" = 1 ] && [ "$dry" = 0 ]; then
  echo
  (cd "$target" && bash scripts/check-agent-guides.sh) || { echo "guide check failed: see MISSING lines above" >&2; exit 1; }
fi
if [ "$layer" = all ] && [ "$dry" = 0 ]; then
  echo
  echo "Next: fill docs/airgap/site-facts.md; per developer: cp .claude/settings.local.example.json .claude/settings.local.json"
fi
