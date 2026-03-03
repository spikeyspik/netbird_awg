#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
DIST_DIR="$NETBIRD_DIR/dist"

if ! command -v pkgbuild >/dev/null 2>&1; then
  echo "[error] pkgbuild is not installed"
  exit 1
fi

if [[ ! -d "$DIST_DIR" ]]; then
  echo "[error] dist directory not found: $DIST_DIR"
  exit 1
fi

release_version="${NETBIRD_RELEASE_TAG#v}"
base_core="${NETBIRD_BASE_TAG#v}"
base_core="${base_core%%-*}"

if [[ "$base_core" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  pkg_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
else
  pkg_version="0.0.0"
fi

ui_amd64="$(find "$DIST_DIR" -type f -path "*/netbird-ui-darwin_darwin_amd64*/netbird-ui" | sort | head -n 1 || true)"
ui_arm64="$(find "$DIST_DIR" -type f -path "*/netbird-ui-darwin_darwin_arm64*/netbird-ui" | sort | head -n 1 || true)"
netbird_amd64="$(find "$DIST_DIR" -type f -path "*_darwin_amd64*/netbird" | sort | head -n 1 || true)"
netbird_arm64="$(find "$DIST_DIR" -type f -path "*_darwin_arm64*/netbird" | sort | head -n 1 || true)"

if [[ -z "$ui_amd64" || -z "$ui_arm64" ]]; then
  echo "[error] netbird-ui darwin binaries are missing in dist/"
  find "$DIST_DIR" -maxdepth 3 -type f | sort
  exit 1
fi

if [[ -z "$netbird_amd64" || -z "$netbird_arm64" ]]; then
  echo "[error] netbird darwin binaries are missing in dist/"
  find "$DIST_DIR" -maxdepth 3 -type f | sort
  exit 1
fi

create_app_icon_icns() {
  local out_icns="$1"
  local src_png="$NETBIRD_DIR/client/ui/assets/netbird.png"
  local fallback_icns="$NETBIRD_DIR/client/ui/Netbird.icns"

  if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [[ -f "$src_png" ]]; then
    local tmp_dir iconset
    tmp_dir="$(mktemp -d)"
    iconset="$tmp_dir/Netbird.iconset"
    mkdir -p "$iconset"

    sips -z 16 16 "$src_png" --out "$iconset/icon_16x16.png" >/dev/null
    sips -z 32 32 "$src_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$src_png" --out "$iconset/icon_32x32.png" >/dev/null
    sips -z 64 64 "$src_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$src_png" --out "$iconset/icon_128x128.png" >/dev/null
    sips -z 256 256 "$src_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$src_png" --out "$iconset/icon_256x256.png" >/dev/null
    sips -z 512 512 "$src_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$src_png" --out "$iconset/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$src_png" --out "$iconset/icon_512x512@2x.png" >/dev/null

    if iconutil -c icns "$iconset" -o "$out_icns" >/dev/null 2>&1; then
      rm -rf "$tmp_dir"
      return 0
    fi
    rm -rf "$tmp_dir"
  fi

  if [[ -f "$fallback_icns" ]]; then
    cp "$fallback_icns" "$out_icns"
    return 0
  fi
  return 1
}

build_pkg() {
  local arch="$1"
  local netbird_bin="$2"
  local ui_bin="$3"
  local root
  root="$(mktemp -d)"

  mkdir -p "$root/usr/local/bin"

  local app_name="Netbird.app"
  local app_dir="$root/Applications/$app_name"
  local app_contents="$app_dir/Contents"
  local app_macos="$app_contents/MacOS"
  local app_resources="$app_contents/Resources"
  mkdir -p "$app_macos" "$app_resources"

  cp "$netbird_bin" "$root/usr/local/bin/netbird"

  cp "$root/usr/local/bin/netbird" "$app_macos/netbird"
  cp "$ui_bin" "$app_macos/netbird-ui"
  cp "$ui_bin" "$root/usr/local/bin/netbird-ui"
  chmod 0755 "$root/usr/local/bin/netbird" "$root/usr/local/bin/netbird-ui" "$app_macos/netbird" "$app_macos/netbird-ui"

  if ! create_app_icon_icns "$app_resources/icon.icns"; then
    echo "[warn] failed to create app icon icns; app bundle will use default icon"
  fi

  cat > "$app_contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Netbird</string>
  <key>CFBundleDisplayName</key>
  <string>Netbird</string>
  <key>CFBundleExecutable</key>
  <string>netbird-ui</string>
  <key>CFBundleIdentifier</key>
  <string>io.netbird.client</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <string>1</string>
  <key>CFBundleIconFile</key>
  <string>icon.icns</string>
  <key>CFBundleShortVersionString</key>
  <string>${pkg_version}</string>
  <key>CFBundleVersion</key>
  <string>${pkg_version}</string>
  <key>CFBundleVersionString</key>
  <string>${pkg_version}</string>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

  local out_pkg="$DIST_DIR/netbird_${release_version}_darwin_${arch}.pkg"
  rm -f "$out_pkg"

  pkgbuild \
    --root "$root" \
    --scripts "$NETBIRD_DIR/release_files/darwin_pkg" \
    --identifier "io.netbird.client" \
    --version "$pkg_version" \
    --install-location "/" \
    "$out_pkg"

  rm -rf "$root"
  echo "[ok] darwin pkg created: $out_pkg"
}

build_pkg amd64 "$netbird_amd64" "$ui_amd64"
build_pkg arm64 "$netbird_arm64" "$ui_arm64"
