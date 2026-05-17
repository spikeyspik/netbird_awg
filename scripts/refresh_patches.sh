#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/patches}"

main() {
  git \
    -c format.signoff=false \
    -C "$NETBIRD_DIR" \
    format-patch "$NETBIRD_BASE_TAG" \
    -o "$PATCH_DIR/netbird" \
    --no-numbered \
    --no-signature \
    --no-stat \
    --zero-commit
}

main "$@"
