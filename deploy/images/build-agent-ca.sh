#!/usr/bin/env bash
# Build and push the agent images with our CA, one per preset in AGENT_PRESETS (site/deploy.env):
#   <REG_OPTIO>/optio-agent-<preset>:<OPTIO_VERSION>  →  …:<OPTIO_VERSION>-<CA_TAG>
# values/values.yaml then points agent.image at them (tag "<V>-<CA_TAG>"; Optio derives the preset
# images from agent.image.prefix + preset + tag).
#
#   images/build-agent-ca.sh [--no-push]
#
# A tag that already exists in the registry is refused: bump CA_TAG (ca2, ca3, …) when the CA changes.
# Needs docker, podman or buildah (BUILDER) and the registry login.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

push=1
[ "${1:-}" = --no-push ] && push=0
load_deploy_env
[ -f "$CA_FILE" ] || die "CA_FILE $CA_FILE is missing"
ctx="$(mktemp -d)"
trap 'rm -rf "$ctx"' EXIT
cp images/agent-ca.Dockerfile "$ctx/Dockerfile"
cp "$CA_FILE" "$ctx/ca.crt"

build() {
  case "$BUILDER" in
    buildah) buildah bud --build-arg "BASE=$1" -t "$2" "$ctx" ;;
    *) "$BUILDER" build --build-arg "BASE=$1" -t "$2" "$ctx" ;;
  esac
}

for p in $AGENT_PRESETS; do
  base="$REG_OPTIO/optio-agent-$p:$OPTIO_VERSION"
  out="$base-$CA_TAG"
  if { command -v skopeo >/dev/null && skopeo inspect --raw "docker://$out"; } >/dev/null 2>&1 \
    || "$BUILDER" manifest inspect "$out" >/dev/null 2>&1; then
    die "$out already exists: never re-push a tag; set a new CA_TAG in site/deploy.env"
  fi
  note "$out"
  build "$base" "$out"
  if [ "$push" = 1 ]; then "$BUILDER" push "$out"; fi
done
note "done. values/values.yaml: agent.image.tag: \"$OPTIO_VERSION-$CA_TAG\""
