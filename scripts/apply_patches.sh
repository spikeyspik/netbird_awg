#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/patches}"

NETBIRD_DIR="$WORKDIR/repos/netbird"
AWG_GO_DIR="$WORKDIR/repos/amneziawg-go"

apply_or_skip() {
  local repo_dir="$1"
  local patch_file="$2"
  local name="$3"
  local apply_opts=(--ignore-space-change --ignore-whitespace --whitespace=nowarn)

  if [[ ! -f "$patch_file" ]]; then
    echo "[error] missing patch: $patch_file"
    exit 1
  fi

  if git -C "$repo_dir" apply "${apply_opts[@]}" --check "$patch_file" >/dev/null 2>&1; then
    echo "[apply] $name"
    git -C "$repo_dir" apply "${apply_opts[@]}" "$patch_file"
    return 0
  fi

  if git -C "$repo_dir" apply "${apply_opts[@]}" --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "[skip] $name already applied"
    return 0
  fi

  echo "[debug] apply check details for $name"
  git -C "$repo_dir" apply "${apply_opts[@]}" --check -v "$patch_file" || true
  echo "[error] $name cannot be applied cleanly"
  exit 1
}

if [[ ! -d "$NETBIRD_DIR/.git" ]]; then
  echo "[error] netbird source directory not found: $NETBIRD_DIR"
  exit 1
fi

if [[ ! -d "$AWG_GO_DIR/.git" ]]; then
  echo "[error] amneziawg-go source directory not found: $AWG_GO_DIR"
  exit 1
fi

apply_or_skip "$AWG_GO_DIR" "$PATCH_DIR/amneziawg-go.patch" "amneziawg-go.patch"
apply_or_skip "$NETBIRD_DIR" "$PATCH_DIR/netbird.patch" "netbird.patch"

echo "[ok] patches are applied"
