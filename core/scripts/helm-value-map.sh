#!/usr/bin/env bash
# Generate helm/VALUES-MAP.md: each Helm value → the template that uses it → the env var it becomes →
# the code that reads that env var. Also lists the env vars the API reads that the chart never sets,
# and the values.yaml keys no template uses.
#
#   bash scripts/helm-value-map.sh            write helm/VALUES-MAP.md
#   bash scripts/helm-value-map.sh --stdout   print it instead
#   bash scripts/helm-value-map.sh --check    exit 1 when helm/VALUES-MAP.md is missing or out of date
#
# Static and approximate: it reads the templates as text, follows `include` helpers, `with`/`range`
# scopes and `$variables`, and needs no helm. Bash, git, awk, sed, sort only. Output is deterministic.
set -euo pipefail
export LC_ALL=C

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
CHART="helm/optio"
TPL="$CHART/templates"
OUT="helm/VALUES-MAP.md"
mode=write
case "${1:-}" in
  --stdout) mode=stdout ;;
  --check) mode=check ;;
  "") ;;
  *) echo "usage: bash scripts/helm-value-map.sh [--stdout|--check]" >&2; exit 2 ;;
esac
[ -f "$CHART/values.yaml" ] || { echo "no $CHART/values.yaml here" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ── 1. Templates → records "value<TAB>template<TAB>env" ─────────────────────────────────────────────
# Helpers (_*.tpl) are read first so `include "name"` can be expanded to the values the helper uses.
{ ls "$TPL"/_*.tpl 2>/dev/null; find "$TPL" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.tpl' \) ! -name '_*' | sort; } \
  > "$tmp/files"

# shellcheck disable=SC2046
awk '
function push(kind, path) { sp++; skind[sp] = kind; spath[sp] = path }
function scope(   i) { for (i = sp; i > 0; i--) if (skind[i] == "with" || skind[i] == "range") return spath[i]; return "" }
function indefine(   i) { for (i = sp; i > 0; i--) if (skind[i] == "define") return spath[i]; return "" }
function addref(r) { if (r != "" && !((r) in seen)) { seen[r] = 1; refs = refs (refs == "" ? "" : " ") r } }
function relpath(sc, rel) { return sc == "" ? "" : (rel == "" ? sc : sc "." rel) }
# The one value path a $variable stands for ("" when it stands for several, or for a helper).
function onepath(v,   n, a) { if (!(v in varrefs)) return ""; n = split(varrefs[v], a, " "); return (n == 1 && a[1] !~ /^INC:/) ? a[1] : "" }
# Value path of a map argument: .Values.a.b, $.Values.a.b, $root.Values.a.b, (.Values.a.b, $var
function basepath(tok,   t) {
  t = tok; sub(/^\(+/, "", t); sub(/\)+$/, "", t)
  if (t ~ /^(\$|\$root)?\.Values\.[A-Za-z0-9_.]+$/) { sub(/^.*\.Values\./, "", t); return t }
  if (t ~ /^\$[a-z][A-Za-z0-9_]*$/) return onepath(substr(t, 2))
  return ""
}
# Rewrite lookups into plain value paths so they are read like `.Values.x.y`:
#   (.Values.x | default dict).y   dig "k1" "k2" <default> <map>   index <map> "k1" "k2"
function rewrite(line,   out, s, m, p1, p2, pre, kw, rest, n, tk, i, j, base, path, keys, ok) {
  out = ""; s = line
  while (match(s, /\(\.Values(\.[A-Za-z0-9_]+)+ *\| *default dict\)(\.[A-Za-z0-9_]+)+/)) {
    m = substr(s, RSTART, RLENGTH); p1 = m; sub(/^\(\.Values\./, "", p1); sub(/ *\|.*/, "", p1)
    p2 = m; sub(/^.*\)/, "", p2)
    out = out substr(s, 1, RSTART - 1) ".Values." p1 p2; s = substr(s, RSTART + RLENGTH)
  }
  line = out s
  out = ""; s = line
  while (match(s, /(^|[^A-Za-z0-9_])(dig|index) /)) {
    pre = substr(s, 1, RSTART + RLENGTH - 1); kw = pre; sub(/ $/, "", kw); sub(/.*[^a-z]/, "", kw)
    pre = substr(pre, 1, length(pre) - length(kw) - 1)
    rest = substr(s, RSTART + RLENGTH); n = split(rest, tk, " "); base = ""; path = ""; ok = 0
    if (kw == "dig") {
      for (i = 1; i <= n && i <= 8; i++) if ((base = basepath(tk[i])) != "") break
      if (base != "" && i >= 2) {
        keys = ""; ok = 1
        for (j = 1; j < i - 1; j++) { if (tk[j] !~ /^"[A-Za-z0-9_]+"$/) { ok = 0; break }; keys = keys "." substr(tk[j], 2, length(tk[j]) - 2) }
        path = base keys
      }
    } else {
      base = basepath(tk[1]); keys = ""
      for (i = 2; i <= n && tk[i] ~ /^"[A-Za-z0-9_]+"\)*$/; i++) { m = tk[i]; gsub(/["()]/, "", m); keys = keys "." m }
      if (base != "" && keys != "") { ok = 1; path = base keys }
    }
    if (ok && path != "") {
      out = out pre ".Values." path " "
      s = ""; for (j = i + (kw == "dig" ? 1 : 0); j <= n; j++) s = s tk[j] " "
    } else { out = out pre kw " "; s = rest }
  }
  return out s
}
function scanrefs(line,   s, m, act, a, v, n, vv, i, sc, suf, p) {
  s = line
  while (match(s, /\.Values(\.[A-Za-z0-9_]+)+/)) { addref(substr(s, RSTART + 8, RLENGTH - 8)); s = substr(s, RSTART + RLENGTH) }
  s = line
  while (match(s, /(include|template) "[^"]+"/)) {
    m = substr(s, RSTART, RLENGTH); sub(/^(include|template) "/, "", m); sub(/"$/, "", m)
    addref("INC:" m); s = substr(s, RSTART + RLENGTH)
  }
  sc = scope()
  s = line
  while (match(s, /\{\{[^}]*\}\}/)) {
    act = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    if (sc != "") {
      a = act
      while (match(a, /[ (]\.[a-z][A-Za-z0-9_]*(\.[a-z][A-Za-z0-9_]*)*/)) {
        m = substr(a, RSTART + 2, RLENGTH - 2); addref(relpath(sc, m)); a = substr(a, RSTART + RLENGTH)
      }
      if (act ~ /^\{\{-? *\. *(\||-?\}\})/) addref(sc)
    }
    a = act
    while (match(a, /\$[a-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*/)) {
      v = substr(a, RSTART + 1, RLENGTH - 1); a = substr(a, RSTART + RLENGTH)
      suf = ""; if (index(v, ".")) { suf = substr(v, index(v, ".")); v = substr(v, 1, index(v, ".") - 1) }
      if (suf ~ /^\.Values\./ || suf ~ /^\.[A-Z]/) continue
      p = onepath(v)
      if (suf != "" && p != "") addref(p suf)
      else if (v in varrefs) { n = split(varrefs[v], vv, " "); for (i = 1; i <= n; i++) addref(vv[i]) }
    }
  }
}
FNR == 1 { file = FILENAME; sub(/.*\//, "", file); sp = 0; pending = ""; pind = -1; ifrefs = ""; split("", varrefs); split("", listvar) }
{
  line = rewrite($0)
  refs = ""; split("", seen)
  scanrefs(line)

  # $var := …   (values on the right-hand side belong to the variable)
  if (match(line, /\$[a-z][A-Za-z0-9_]*(, *\$[a-z][A-Za-z0-9_]*)? *:= */)) {
    lhs = substr(line, RSTART, RLENGTH); gsub(/[ :=]/, "", lhs); n = split(lhs, lv, ",")
    # a `lookup` reads a live Kubernetes object, not a value
    varrefs[substr(lv[n], 2)] = (line ~ /lookup "/) ? "" : refs
  }
  # range $env := list "A" "B"   → env names for a later `{{ $env }}:` line
  if (match(line, /range \$[a-z][A-Za-z0-9_]* := list( "[A-Z][A-Z0-9_]*")+/)) {
    m = substr(line, RSTART, RLENGTH); v = m; sub(/^range \$/, "", v); sub(/ .*/, "", v)
    sub(/^[^"]*/, "", m); gsub(/"/, "", m); listvar[v] = m
  }

  # Which env var(s) this line defines
  # A container env entry "- name: X" owns the lines indented deeper than its dash (value:, valueFrom:, …).
  env = ""
  if (match(line, /- name: *[A-Z][A-Z0-9_]+[ \t]*$/)) {
    m = substr(line, RSTART, RLENGTH); sub(/^- name: */, "", m); sub(/[ \t]+$/, "", m); pending = m; pind = RSTART - 1; env = m
  } else if (pending != "") {
    match(line, /^ */)
    if (line !~ /^[ \t]*$/ && RLENGTH > pind) env = pending; else pending = ""
  }
  if (env == "" && match(line, /^[ \t]*[A-Z][A-Z0-9_]+:([ \t]|$)/)) {
    m = substr(line, RSTART, RLENGTH); gsub(/[ \t:]/, "", m); env = m
    if (refs == "") { refs = ifrefs; sub(/(^| )existingSecrets( |$)/, " ", refs); gsub(/^ +| +$/, "", refs) }   # ENV: "true" under {{ if .Values.x }}
  }
  if (env == "" && match(line, /\{\{-? *\$[a-z][A-Za-z0-9_]* *-?\}\}:/)) {
    m = substr(line, RSTART, RLENGTH); sub(/^\{\{-? *\$/, "", m); sub(/[ -]*\}\}:$/, "", m)
    if (m in listvar) env = listvar[m]
  }

  d = indefine()
  if (d != "") { if (refs != "") defs[d] = defs[d] " " refs }
  else if (refs != "" && line !~ /^[ \t]*\{\{-? *\$[a-z][A-Za-z0-9_]* *:=[^}]*-?\}\}[ \t]*$/) { nl++; rfile[nl] = file; renv[nl] = env; rrefs[nl] = refs }
  ifrefs = (line ~ /^[ \t]*\{\{-? *(if|else if) [^}]*\}\}[ \t]*$/) ? refs : ""

  # Update the block stack from this line'"'"'s actions, in order.
  s = line
  while (match(s, /\{\{-? *(if|with|range|define|block|end)[ "}-]/)) {
    act = substr(s, RSTART); s = substr(s, RSTART + RLENGTH)
    if (act ~ /^\{\{-? *end/) { if (sp > 0) sp--; continue }
    if (act ~ /^\{\{-? *define/) { m = act; sub(/^[^"]*"/, "", m); sub(/".*/, "", m); push("define", m); continue }
    if (act ~ /^\{\{-? *if/) { push("if", ""); continue }
    if (act ~ /^\{\{-? *block/) { push("block", ""); continue }
    kind = (act ~ /^\{\{-? *with/) ? "with" : "range"
    p = ""
    if (match(act, /^[^}]*\.Values(\.[A-Za-z0-9_]+)+/)) { m = substr(act, 1, RLENGTH); sub(/.*\.Values\./, "", m); p = m }
    else if (match(act, /^\{\{-? *(with|range) +\.[a-z][A-Za-z0-9_.]*/)) { m = substr(act, 1, RLENGTH); sub(/^.*[ ]\./, "", m); p = relpath(scope(), m) }
    else if (match(act, /^\{\{-? *(with|range) +\$[a-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)*/)) {
      m = substr(act, 1, RLENGTH); sub(/^.*\$/, "", m); v = m; sub(/\..*/, "", v); suf = substr(m, length(v) + 1)
      if (onepath(v) != "") p = onepath(v) suf
    }
    else if (match(act, /^\{\{-? *range +\$[a-z][A-Za-z0-9_]*, *\$[a-z][A-Za-z0-9_]* *:= *\.Values(\.[A-Za-z0-9_]+)+/)) { m = substr(act, 1, RLENGTH); sub(/.*\.Values\./, "", m); p = m }
    if (kind == "range" && match(act, /\$[a-z][A-Za-z0-9_]* *:=/) && p != "") {
      m = substr(act, RSTART + 1, RLENGTH - 1); sub(/[ :=]+$/, "", m); varrefs[m] = p ".*"
      if (match(act, /, *\$[a-z][A-Za-z0-9_]* *:=/)) { m = substr(act, RSTART, RLENGTH); gsub(/[ ,:=$]/, "", m); varrefs[m] = p ".*" }
    }
    push(kind, (kind == "range" && p != "") ? p ".*" : p)
  }
}
function expand(tok, depth,   n, t, i, out) {
  if (tok !~ /^INC:/) return tok
  if (depth > 8) return ""
  n = split(defs[substr(tok, 5)], t, " "); out = ""
  for (i = 1; i <= n; i++) out = out " " expand(t[i], depth + 1)
  return out
}
END {
  for (i = 1; i <= nl; i++) {
    n = split(rrefs[i], t, " ")
    for (j = 1; j <= n; j++) {
      m = split(expand(t[j], 0), u, " ")
      for (k = 1; k <= m; k++) {
        if (u[k] == "") continue
        ne = split(renv[i], ev, " ")
        if (ne == 0) print u[k] "\t" rfile[i] "\t"
        for (e = 1; e <= ne; e++) print u[k] "\t" rfile[i] "\t" ev[e]
      }
    }
  }
}' $(cat "$tmp/files") | sort -u > "$tmp/records"

# ── 2. values.yaml leaf keys (to find values no template uses) ─────────────────────────────────────
awk '
/^[ \t]*#/ || /^[ \t]*$/ { next }
{
  match($0, /^ */); ind = RLENGTH; line = substr($0, ind + 1)
  if (blockind >= 0 && ind > blockind) next
  blockind = -1
  if (listind >= 0 && (ind > listind || (ind == listind && line ~ /^- /))) next
  listind = -1
  if (line ~ /^- /) { if (sp > 0) leaf[spath[sp]] = 1; listind = ind; next }
  if (!match(line, /^[A-Za-z0-9_.\/-]+:( |$)/)) next
  key = substr(line, 1, RLENGTH); sub(/: ?$/, "", key); rest = substr(line, RLENGTH + 1)
  while (sp > 0 && sind[sp] >= ind) sp--
  if (sp > 0) parent[spath[sp]] = 1
  path = (sp > 0 ? spath[sp] "." : "") key
  sp++; sind[sp] = ind; spath[sp] = path; order[++no] = path
  sub(/[ \t]+#.*$/, "", rest)
  if (rest ~ /^[|>]/) { leaf[path] = 1; blockind = ind } else if (rest != "") leaf[path] = 1
}
BEGIN { blockind = -1; listind = -1 }
END { for (i = 1; i <= no; i++) { p = order[i]; if (leaf[p] || !(p in parent)) print p } }' "$CHART/values.yaml" | sort -u > "$tmp/leaves"

cut -f1 "$tmp/records" | sort -u > "$tmp/refs"
awk 'NR == FNR { ref[$0] = 1; next }
     { p = $0; used = 0
       for (r in ref) if (r == p || index(p, r ".") == 1 || index(r, p ".") == 1) { used = 1; break }
       if (!used) print p }' "$tmp/refs" "$tmp/leaves" > "$tmp/unused"

# ── 3. Who reads each env var ──────────────────────────────────────────────────────────────────────
# Source code only (no migrations, docs or tests). In a git pathspec `*` also matches `/`.
code_paths() { local d e; for d in "$@"; do for e in ts tsx mjs js; do printf '%s\n' "$d/*.$e"; done; done; }
CODE=(); while IFS= read -r l; do CODE+=("$l"); done < <(code_paths apps/api/src apps/web/src apps/cli/src packages)
EXCL=(':!*.test.ts' ':!*.test.tsx' ':!*.test.mjs' ':!*.d.ts' ':!**/test-utils/**' ':!**/e2e/**' ':!**/__tests__/**' ':!**/__fixtures__/**')
readers() {
  local files
  files="$(git grep -l -w -F -e "$1" -- "${CODE[@]}" "${EXCL[@]}" 2>/dev/null | sort || true)"
  [ -n "$files" ] || { echo "—"; return; }
  local n; n="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
  printf '%s\n' "$files" | head -2 | sed 's/.*/`&`/' | paste -sd ',' - | sed 's/,/, /g' | tr -d '\n'
  [ "$n" -le 2 ] || printf ' +%s' "$((n - 2))"
  echo
}
cut -f3 "$tmp/records" | grep -v '^$' | sort -u > "$tmp/envs" || true
: > "$tmp/readers"
while IFS= read -r e; do printf '%s\t%s\n' "$e" "$(readers "$e")" >> "$tmp/readers"; done < "$tmp/envs"

# Env vars the API process reads that the chart never mentions.
API_CODE=(); while IFS= read -r l; do API_CODE+=("$l"); done < <(code_paths apps/api/src packages/shared/src packages/ticket-providers/src packages/agent-adapters/src packages/container-runtime/src)
git grep -h -o -E 'process\.env(\.[A-Z][A-Z0-9_]+|\["[A-Z][A-Z0-9_]+"\])|[A-Za-z]+Env\( *"[A-Z][A-Z0-9_]+"' -- "${API_CODE[@]}" "${EXCL[@]}" 2>/dev/null \
  | grep -o -E '[A-Z][A-Z0-9_]{2,}' | sort -u > "$tmp/api-envs" || true
cat "$TPL"/* "$TPL"/*/* 2>/dev/null | grep -o -E '[A-Z][A-Z0-9_]{2,}' | sort -u > "$tmp/chart-words" || true
for f in Dockerfile.api Dockerfile.web; do [ -f "$f" ] && grep -o -E '^ENV [A-Z][A-Z0-9_]+|^ +[A-Z][A-Z0-9_]+=' "$f" | grep -o -E '[A-Z][A-Z0-9_]+' | grep -v '^ENV$'; done \
  | sort -u > "$tmp/docker-envs" || true
comm -23 "$tmp/api-envs" "$tmp/chart-words" | comm -23 - "$tmp/docker-envs" \
  | grep -v -E '^(HOME|PATH|USER|PWD|SHELL|TERM|HOSTNAME|TMPDIR|LANG|CI|VITEST|JEST_WORKER_ID)$' > "$tmp/unset" || true

# ── 4. Render ──────────────────────────────────────────────────────────────────────────────────────
render() {
  cat <<'EOF'
# Helm values → templates → env vars → code

<!-- Generated by scripts/helm-value-map.sh from helm/optio. Do not edit by hand: re-run the script.
     scripts/check-agent-guides.sh fails when this file is out of date. -->

How to use it: grep for a value (`grep -n "outbound" helm/VALUES-MAP.md`) or an env var
(`grep -n "GITLAB_HOSTS" helm/VALUES-MAP.md`). Templates are in `helm/optio/templates/`.
"Env var" is what the template renders the value into (mostly the `<release>-config` Secret, loaded into
the API container with `envFrom`). "Read by" lists the first source files that use that env var.
A value with no env var is used directly in a Kubernetes object (replicas, ports, volumes, …).
This is a static reading of the templates: conditions (`if`) are ignored, so a row means "can render".

EOF
  awk -F'\t' '
    NR == FNR { rd[$1] = $2; next }
    { v = $1; t = $2; e = $3
      if (!(v in tpls)) { order[++n] = v }
      if (index(" " tpls[v] " ", " " t " ") == 0) tpls[v] = tpls[v] (tpls[v] == "" ? "" : " ") t
      if (e != "" && index(" " envs[v] " ", " " e " ") == 0) envs[v] = envs[v] (envs[v] == "" ? "" : " ") e }
    END {
      for (i = 1; i <= n; i++) {
        v = order[i]; top = v; sub(/\..*/, "", top)
        if (top != last) { if (last != "") print ""; print "## " top; print ""; print "| Value | Template | Env var | Read by |"; print "| --- | --- | --- | --- |"; last = top }
        nt = split(tpls[v], ta, " "); ts = ""
        for (j = 1; j <= nt; j++) ts = ts (j > 1 ? ", " : "") "`" ta[j] "`"
        ne = split(envs[v], ea, " "); es = ""; rs = ""
        for (j = 1; j <= ne; j++) {
          es = es (j > 1 ? ", " : "") "`" ea[j] "`"
          if (ne <= 3) rs = rs (rs == "" ? "" : "; ") rd[ea[j]]
        }
        if (ne > 3) rs = "(several)"
        if (ne == 0) { es = "—"; rs = "—" }
        print "| `" v "` | " ts " | " es " | " rs " |"
      }
    }' "$tmp/readers" "$tmp/records-ordered"

  echo
  echo "## Env vars the API reads that the chart never sets"
  echo
  echo "Read with \`process.env\` in the API process (apps/api and the packages it loads) but not mentioned in"
  echo "any template, so the chart has no value for them. Set one with \`existingSecrets\` (a key in a Secret you"
  echo "own) or a chart change. Some are development or test switches."
  echo
  if [ -s "$tmp/unset" ]; then
    echo "| Env var | Read by |"
    echo "| --- | --- |"
    while IFS= read -r e; do
      printf '| `%s` | %s |\n' "$e" "$(git grep -l -w -F -e "$e" -- "${API_CODE[@]}" "${EXCL[@]}" 2>/dev/null | sort | head -2 | sed 's/.*/`&`/' | paste -sd ',' - | sed 's/,/, /g')"
    done < "$tmp/unset"
  else
    echo "None."
  fi

  echo
  echo "## values.yaml keys no template uses"
  echo
  echo "Setting these changes nothing in the rendered chart (they may be documentation, or read by something"
  echo "outside the templates)."
  echo
  if [ -s "$tmp/unused" ]; then sed 's/.*/- `&`/' "$tmp/unused"; else echo "None."; fi
}

# Rows in values.yaml order (top-level section order, then path order within it).
grep -E '^[A-Za-z][A-Za-z0-9_]*:' "$CHART/values.yaml" | cut -d: -f1 | awk '{ print NR "\t" $0 }' > "$tmp/toporder"
awk -F'\t' 'NR == FNR { o[$2] = $1; next } { top = $1; sub(/\..*/, "", top); print (top in o ? o[top] : 999) "\t" $0 }' \
  "$tmp/toporder" "$tmp/records" | sort -t "$(printf '\t')" -k1,1n -k2,2 -k3,3 -k4,4 | cut -f2- > "$tmp/records-ordered"

render > "$tmp/out"

case "$mode" in
  stdout) cat "$tmp/out" ;;
  write) mkdir -p "$(dirname "$OUT")"; cp "$tmp/out" "$OUT"; echo "wrote $OUT ($(grep -c '^| `' "$OUT") rows)" ;;
  check)
    if [ ! -f "$OUT" ]; then echo "STALE  $OUT is missing: run bash scripts/helm-value-map.sh"; exit 1; fi
    if ! cmp -s "$tmp/out" "$OUT"; then echo "STALE  $OUT is out of date with helm/optio: run bash scripts/helm-value-map.sh"; exit 1; fi
    ;;
esac
