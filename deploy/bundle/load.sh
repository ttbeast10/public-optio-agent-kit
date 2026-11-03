#!/usr/bin/env bash
# INSIDE the air gap: check a carried-in bundle (from bundle/fetch.sh), push its images to our
# registry, and put the chart and the backup scripts where the deploy scripts look for them.
#
#   bundle/load.sh <path to optio-bundle-<version>>
#
# Images go to REG_OPTIO (optio/…) and REG_MIRROR (mirror/…) from site/deploy.env. An image whose tag
# already exists is skipped: never re-push a tag (nodes cache by tag).
# Needs skopeo, or docker / podman (LOADER=docker|podman). Log in to the registry first.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

B="$(cd "${1:?usage: bundle/load.sh <bundle folder>}" && pwd)"
load_deploy_env
LOADER="${LOADER:-skopeo}"

note "checksums"
(cd "$B" && sha256sum -c --quiet SHA256SUMS) || die "checksum mismatch in $B"

exists() {
  case "$LOADER" in
    skopeo) skopeo inspect --raw "docker://$1" >/dev/null 2>&1 ;;
    *) "$LOADER" manifest inspect "$1" >/dev/null 2>&1 ;;
  esac
}

while read -r file src dest; do
  case "$dest" in
    optio/*) target="$REG_OPTIO/${dest#optio/}" ;;
    mirror/*) target="$REG_MIRROR/${dest#mirror/}" ;;
    *) die "unknown destination $dest in MANIFEST.txt" ;;
  esac
  if exists "$target"; then
    echo "have  $target"
    continue
  fi
  echo "push  $target   (from $src)"
  case "$LOADER" in
    skopeo) skopeo copy "docker-archive:$B/$file" "docker://$target" ;;
    *)
      loaded="$("$LOADER" load -i "$B/$file" | sed -nE 's/^Loaded image: (.*)$/\1/p' | tail -1)"
      "$LOADER" tag "$loaded" "$target"
      "$LOADER" push "$target"
      ;;
  esac
done < "$B/MANIFEST.txt"

v="$(ls "$B"/optio-*.tgz | sed -E 's/.*optio-(.*)\.tgz/\1/')"
cp "$B/optio-$v.tgz" bundle/
mkdir -p bundle/backup
cp "$B"/backup/*.sh bundle/backup/
chmod +x bundle/backup/*.sh
note "chart bundle/optio-$v.tgz and bundle/backup/ in place."
note "Next: OPTIO_VERSION=\"$v\" in site/deploy.env, then images/build-agent-ca.sh"
