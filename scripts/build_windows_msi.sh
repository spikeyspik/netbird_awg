#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
DIST_DIR="$NETBIRD_DIR/dist"
WIX_VERSION="${WIX_VERSION:-5.0.2}"

if ! command -v wix >/dev/null 2>&1; then
  echo "[error] wix is not installed (dotnet tool wix)"
  exit 1
fi

if [[ ! -d "$DIST_DIR" ]]; then
  echo "[error] dist directory not found: $DIST_DIR"
  exit 1
fi

wxs_file="$NETBIRD_DIR/client/netbird.wxs"
if [[ ! -f "$wxs_file" ]]; then
  echo "[error] wix source file not found: $wxs_file"
  exit 1
fi

release_version="${NETBIRD_RELEASE_TAG#v}"
base_core="${NETBIRD_BASE_TAG#v}"
base_core="${base_core%%-*}"

if [[ ! "$base_core" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[error] invalid NETBIRD_BASE_TAG for MSI version: $NETBIRD_BASE_TAG"
  exit 1
fi

staging_dir="$DIST_DIR/netbird_windows_amd64"
if [[ ! -d "$staging_dir" ]]; then
  echo "[error] expected staging directory is missing: $staging_dir"
  echo "[hint] run ./scripts/build_windows_installer.sh first"
  exit 1
fi

pick_file() {
  local target="$1"
  shift
  local src=""
  for candidate in "$@"; do
    if [[ -f "$staging_dir/$candidate" ]]; then
      src="$staging_dir/$candidate"
      break
    fi
  done

  if [[ -z "$src" ]]; then
    echo "[error] required file is missing in $staging_dir: $target"
    exit 1
  fi

  if [[ "$src" != "$staging_dir/$target" ]]; then
    cp -f "$src" "$staging_dir/$target"
  fi
}

# netbird.wxs references lowercase file names.
pick_file "netbird.exe" "netbird.exe" "Netbird.exe"
pick_file "netbird-ui.exe" "netbird-ui.exe" "Netbird-ui.exe"
pick_file "wintun.dll" "wintun.dll" "Wintun.dll"
pick_file "opengl32.dll" "opengl32.dll" "OpenGL32.dll"

artifact_path="$DIST_DIR/netbird_installer_${release_version}_windows_amd64.msi"
tmp_msi="$NETBIRD_DIR/netbird-installer.msi"
rm -f "$tmp_msi" "$artifact_path"

run_wix_build_with_util() {
  (
    cd "$NETBIRD_DIR"
    NETBIRD_VERSION="$base_core" wix build \
      -arch x64 \
      -d ArchSuffix=amd64 \
      -d ProcessorArchitecture=x64 \
      -ext WixToolset.Util.wixext \
      -o "$tmp_msi" \
      "client/netbird.wxs"
  )
}

has_wix_util_extension() {
  wix extension list | grep -Eq 'WixToolset\.Util\.wixext'
}

ensure_wix_util_extension() {
  local wix_ext="WixToolset.Util.wixext"

  if has_wix_util_extension; then
    return 0
  fi

  wix extension add "$wix_ext" || true
  wix extension add -g "$wix_ext" || true

  if has_wix_util_extension; then
    return 0
  fi

  echo "[error] required WiX extension is unavailable: $wix_ext"
  echo "[error] MSI build requires WixToolset.Util.wixext and will not fallback"
  wix extension list || true
  return 1
}

ensure_wix_util_extension
run_wix_build_with_util

if [[ ! -f "$tmp_msi" ]]; then
  echo "[error] expected msi is missing: $tmp_msi"
  exit 1
fi

mv -f "$tmp_msi" "$artifact_path"
echo "[ok] windows msi created: $artifact_path"
