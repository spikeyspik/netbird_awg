#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
AWG_GO_DIR="${AWG_GO_DIR:-$WORKDIR/repos/amneziawg-go}"
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/patches}"
CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/goreleaser}"

UI_BRAND_NAME="${UI_BRAND_NAME:-NetBird AWG}"
UI_BRAND_COLOR_HEX="${UI_BRAND_COLOR_HEX:-2EA3FF}"
UI_VERSION_LABEL="${UI_VERSION_LABEL:-${UI_BRAND_NAME} ${NETBIRD_RELEASE_TAG}}"

log() {
  echo "[$1] ${*:2}"
}

require_repo() {
  local repo_dir="$1"
  local name="$2"
  if [[ ! -d "$repo_dir/.git" ]]; then
    log error "$name source directory not found: $repo_dir"
    exit 1
  fi
}

apply_or_skip() {
  local repo_dir="$1"
  local patch_file="$2"
  local name="$3"
  local apply_opts=(--ignore-space-change --ignore-whitespace --whitespace=nowarn)

  if [[ ! -f "$patch_file" ]]; then
    log error "missing patch: $patch_file"
    exit 1
  fi

  if git -C "$repo_dir" apply "${apply_opts[@]}" --check "$patch_file" >/dev/null 2>&1; then
    log apply "$name"
    git -C "$repo_dir" apply "${apply_opts[@]}" "$patch_file"
    return 0
  fi

  if git -C "$repo_dir" apply "${apply_opts[@]}" --reverse --check "$patch_file" >/dev/null 2>&1; then
    log skip "$name already applied"
    return 0
  fi

  log debug "apply check details for $name"
  git -C "$repo_dir" apply "${apply_opts[@]}" --check -v "$patch_file" || true
  log error "$name cannot be applied cleanly"
  exit 1
}

apply_patches() {
  apply_or_skip "$AWG_GO_DIR" "$PATCH_DIR/amneziawg-go.patch" "amneziawg-go.patch"
  apply_or_skip "$NETBIRD_DIR" "$PATCH_DIR/netbird.patch" "netbird.patch"
  log ok "patches are applied"
}

replace_imports() {
  while IFS= read -r rel; do
    local file="$NETBIRD_DIR/$rel"
    perl -0pi -e 's#golang\.zx2c4\.com/wireguard/windows#github.com/amnezia-vpn/amneziawg-windows#g; s#golang\.zx2c4\.com/wireguard/(?!wgctrl)#github.com/amnezia-vpn/amneziawg-go/#g;' "$file"
  done < <(git -C "$NETBIRD_DIR" ls-files '*.go' 'go.mod')

  pushd "$NETBIRD_DIR" >/dev/null
  go mod edit -dropreplace=golang.zx2c4.com/wireguard || true
  go mod edit -dropreplace=golang.zx2c4.com/wireguard/windows || true
  go mod edit -dropreplace=github.com/amnezia-vpn/amneziawg-go || true
  go mod edit -dropreplace=github.com/amnezia-vpn/amneziawg-windows || true
  go mod edit -replace=github.com/amnezia-vpn/amneziawg-go=../amneziawg-go
  go mod edit -replace=github.com/amnezia-vpn/amneziawg-windows=../amneziawg-windows
  go mod tidy
  popd >/dev/null

  local count
  count="$(
    (
      git -C "$NETBIRD_DIR" grep -nE \
        "github.com/amnezia-vpn/amneziawg-go|github.com/amnezia-vpn/amneziawg-windows|golang.zx2c4.com/wireguard" \
        -- '*.go' 'go.mod' || true
    ) | wc -l | tr -d ' '
  )"
  log ok "awg replace completed, touched patterns=$count"
}

set_netbird_version() {
  local version_file="$NETBIRD_DIR/version/version.go"
  if [[ ! -f "$version_file" ]]; then
    log error "version file not found: $version_file"
    exit 1
  fi

  perl -0pi -e 's/var version = "[^"]*"/var version = "'"$NETBIRD_RELEASE_TAG"'"/g' "$version_file"
  local current
  current="$(grep -n '^var version = ' "$version_file" | head -n 1 | sed 's/.*= //')"
  log ok "netbird source version set to $current"
}

brand_ui() {
  if ! command -v go >/dev/null 2>&1; then
    log error "go is required for UI branding"
    exit 1
  fi

  go run "$SCRIPT_DIR/brand_netbird_ui.go" \
    --netbird-dir "$NETBIRD_DIR" \
    --brand-name "$UI_BRAND_NAME" \
    --version-label "$UI_VERSION_LABEL" \
    --brand-color-hex "$UI_BRAND_COLOR_HEX"

  log ok "netbird-ui branding is applied (icon color + ui labels)"
}

install_goreleaser_configs() {
  local cfg
  for cfg in \
    ".goreleaser.awg.yaml" \
    ".goreleaser.awg.nfpm.yaml" \
    ".goreleaser.awg.installers.yaml"
  do
    if [[ ! -f "$CONFIG_DIR/$cfg" ]]; then
      log error "missing goreleaser config: $CONFIG_DIR/$cfg"
      exit 1
    fi
    cp "$CONFIG_DIR/$cfg" "$NETBIRD_DIR/$cfg"
    log ok "installed goreleaser config: $NETBIRD_DIR/$cfg"
  done
}

main() {
  require_repo "$NETBIRD_DIR" "netbird"
  require_repo "$AWG_GO_DIR" "amneziawg-go"

  apply_patches
  replace_imports
  set_netbird_version
  brand_ui
  install_goreleaser_configs

  log ok "sources are prepared for goreleaser"
}

main "$@"
