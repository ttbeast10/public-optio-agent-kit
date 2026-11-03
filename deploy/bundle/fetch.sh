#!/usr/bin/env bash
# OUTSIDE the air gap, on a machine with internet: download everything one Optio release needs into
# one folder, to carry in through your approved transfer process. Contains no site data.
#
#   bundle/fetch.sh <version> [preset ...]        e.g.  bundle/fetch.sh 0.23.0 node python
#
# Writes optio-bundle-<version>/:
#   optio-<version>.tgz        the chart (oci://ghcr.io/jonwiggins/optio)
#   images/*.tar               docker-archive files: api, web, agent-base + the presets you name,
#                              and the third-party images the chart uses (PostgreSQL, Redis, Envoy,
#                              the busybox its init containers hardcode; alpine/k8s with BACKUP_S3=1)
#   backup/*.sh                upstream's backup / restore scripts for that version (plain bash + kubectl)
#   MANIFEST.txt               "<archive> <source> <destination>" per image, read by bundle/load.sh
#   SHA256SUMS
# Needs helm 3.8+, skopeo, curl, tar. ARCH=amd64 by default (one architecture keeps the archives small).
set -euo pipefail

V="${1:?usage: bundle/fetch.sh <version> [preset ...]}"
shift
PRESETS=(base "$@")
ARCH="${ARCH:-amd64}"
OUT="optio-bundle-$V"
UP="https://raw.githubusercontent.com/jonwiggins/optio/v$V"
mkdir -p "$OUT/images" "$OUT/backup"
cd "$OUT"

echo "--- chart"
helm pull oci://ghcr.io/jonwiggins/optio --version "$V"
tar -xzf "optio-$V.tgz" optio/values.yaml optio/templates

# repository:tag pairs from the chart's own values, so the mirrored versions are the tested ones.
chart_image() {
  awk -v want="$1" '
    /repository:/ { r = $2; gsub(/"/, "", r) }
    /tag:/ && r == want { t = $2; gsub(/"/, "", t); print r ":" t; exit }
  ' optio/values.yaml
}

: > MANIFEST.txt
add() { # add <source> <destination relative to REG_OPTIO "optio/…" or REG_MIRROR "mirror/…">
  local src="$1" dest="$2" file
  file="images/$(echo "$dest" | tr '/:' '__').tar"
  echo "--- $src"
  skopeo copy --override-os linux --override-arch "$ARCH" "docker://$src" \
    "docker-archive:$file:${dest#*/}"
  echo "$file $src $dest" >> MANIFEST.txt
}

for c in api web; do
  add "ghcr.io/jonwiggins/optio-$c:$V" "optio/optio-$c:$V"
done
for p in "${PRESETS[@]}"; do
  add "ghcr.io/jonwiggins/optio-agent-$p:$V" "optio/optio-agent-$p:$V"
done

# "16@sha256:…" → source by digest (skopeo takes a tag or a digest, not both), destination by tag.
src_of() { case "$1" in *@*) echo "${1%%:*}@${1#*@}" ;; *) echo "$1" ;; esac; }
tag_of() { local t="${1#*:}"; echo "${t%%@*}"; }
pg="$(chart_image postgres)"
redis="$(chart_image redis)"
envoy="$(chart_image envoyproxy/envoy)"
add "docker.io/library/$(src_of "$pg")" "mirror/library/postgres:$(tag_of "$pg")"
add "docker.io/library/$(src_of "$redis")" "mirror/library/redis:$(tag_of "$redis")"
add "docker.io/$(src_of "$envoy")" "mirror/envoyproxy/envoy:$(tag_of "$envoy")"
for b in $(grep -rhoE 'image: busybox:[0-9.]+' optio/templates | sort -u | awk '{print $2}'); do
  add "docker.io/library/$b" "mirror/library/$b"
done
if [ "${BACKUP_S3:-0}" = 1 ]; then
  k8s="$(chart_image alpine/k8s)"
  add "docker.io/$(src_of "$k8s")" "mirror/alpine/k8s:$(tag_of "$k8s")"
fi
rm -rf optio

echo "--- backup scripts"
for s in backup-db.sh backup-lib.sh restore-db.sh; do
  curl -fsSL "$UP/scripts/backup/$s" -o "backup/$s"
done
chmod +x backup/*.sh

find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
echo "--- done: $(du -sh . | cut -f1) in $OUT/. Carry the whole folder in."
