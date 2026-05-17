#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
REPOS_DIR="$WORKDIR/repos"

NETBIRD_REPO="${NETBIRD_REPO:-https://github.com/netbirdio/netbird.git}"

AWG_GO_REPO="${AWG_GO_REPO:-https://github.com/amnezia-vpn/amneziawg-go.git}"
AWG_GO_REF="${AWG_GO_REF:-449d7cffd4adf86971bd679d0be5384b443e8be5}"

clone_and_checkout() {
  local repo_url="$1"
  local repo_dir="$2"
  local ref="$3"

  if [[ ! -d "$repo_dir/.git" ]]; then
    echo "[clone] $repo_url -> $repo_dir"
    git clone "$repo_url" "$repo_dir"
  fi

  echo "[fetch] $repo_dir"
  git -C "$repo_dir" fetch --tags --force origin

  echo "[checkout] $repo_dir @ $ref"
  git -C "$repo_dir" checkout --force "$ref"
  git -C "$repo_dir" reset --hard "$ref"
  git -C "$repo_dir" clean -fdx
}

mkdir -p "$REPOS_DIR"

clone_and_checkout "$NETBIRD_REPO" "$REPOS_DIR/netbird" "$NETBIRD_REF"
clone_and_checkout "$AWG_GO_REPO" "$REPOS_DIR/amneziawg-go" "$AWG_GO_REF"

echo "[ok] sources are prepared in $REPOS_DIR"
