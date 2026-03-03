#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/version_vars.sh"

WORKDIR="${WORKDIR:-$ROOT_DIR/workdir}"
NETBIRD_DIR="${NETBIRD_DIR:-$WORKDIR/repos/netbird}"
DIST_DIR="$NETBIRD_DIR/dist"
WINRES_DIR="${WINRES_DIR:-$ROOT_DIR/winres}"

if ! command -v makensis >/dev/null 2>&1; then
  echo "[error] makensis is not installed"
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
  nsis_appver="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.0"
else
  nsis_appver="0.0.0.0"
fi

staging_dir="$DIST_DIR/netbird_windows_amd64"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"

netbird_exe="$(find "$DIST_DIR" -type f -path "*_windows_amd64*/netbird.exe" | sort | head -n 1 || true)"
ui_exe="$(
  {
    find "$DIST_DIR" -type f -path "*/netbird-ui-windows-amd64_windows_amd64*/netbird-ui.exe" 2>/dev/null
    find "$DIST_DIR" -type f -path "*/netbird-ui-windows_windows_amd64*/netbird-ui.exe" 2>/dev/null
  } | sort | head -n 1 || true
)"

if [[ -z "$netbird_exe" ]]; then
  echo "[error] netbird.exe for windows amd64 not found in dist/"
  find "$DIST_DIR" -maxdepth 3 -type f | sort
  exit 1
fi
cp "$netbird_exe" "$staging_dir/Netbird.exe"

if [[ -z "$ui_exe" ]]; then
  echo "[error] netbird-ui.exe for windows amd64 not found in dist/"
  find "$DIST_DIR" -maxdepth 3 -type f | sort
  exit 1
fi

cp "$ui_exe" "$staging_dir/Netbird-ui.exe"

if [[ -f "$WINRES_DIR/wintun_amd64.dll" ]]; then
  cp "$WINRES_DIR/wintun_amd64.dll" "$staging_dir/wintun.dll"
else
  dll_src="$(find "$DIST_DIR" -type f -name "wintun.dll" | sort | head -n 1 || true)"
  if [[ -n "$dll_src" ]]; then
    cp "$dll_src" "$staging_dir/wintun.dll"
  fi
fi

if [[ -f "$WINRES_DIR/opengl32.dll" ]]; then
  cp "$WINRES_DIR/opengl32.dll" "$staging_dir/opengl32.dll"
else
  dll_src="$(find "$DIST_DIR" -type f -name "opengl32.dll" | sort | head -n 1 || true)"
  if [[ -n "$dll_src" ]]; then
    cp "$dll_src" "$staging_dir/opengl32.dll"
  fi
fi

plugins_dir="$(find "$DIST_DIR" -type d -name Plugins | sort | head -n 1 || true)"
if [[ -d "$WINRES_DIR/Plugins" ]]; then
  cp -R "$WINRES_DIR/Plugins" "$staging_dir/Plugins"
elif [[ -d "$plugins_dir" ]]; then
  cp -R "$plugins_dir" "$staging_dir/Plugins"
fi

nsis_plugins_dir="$WINRES_DIR/Plugins"
has_nsis_plugins=0
if [[ -d "$nsis_plugins_dir/amd64-unicode" || -d "$nsis_plugins_dir/x86-unicode" ]]; then
  has_nsis_plugins=1
fi

if [[ -n "$plugins_dir" && ! -d "$staging_dir/Plugins" ]]; then
  cp -R "$plugins_dir" "$staging_dir/Plugins"
fi

nsis_src="$NETBIRD_DIR/client/installer.nsis"
nsis_tmp="$NETBIRD_DIR/client/installer.awg.nsis"
trap 'rm -f "$nsis_tmp"' EXIT

to_nsis_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -aw "$path"
  else
    echo "$path"
  fi
}

write_nsis_without_plugins() {
  sed \
    -e '/EnVar::SetHKLM/d' \
    -e '/EnVar::AddValueEx "path" "\$INSTDIR"/d' \
    -e '/EnVar::DeleteValue "path" "\$INSTDIR"/d' \
    -e 's/ShellExecAsUser::ShellExecAsUser/ExecShell/g' \
    "$nsis_src" > "$nsis_tmp"
}

write_nsis_with_plugins() {
  {
    if [[ -d "$nsis_plugins_dir/x86-unicode" ]]; then
      printf '!addplugindir "%s"\n' "$(to_nsis_path "$nsis_plugins_dir/x86-unicode")"
    fi
    if [[ -d "$nsis_plugins_dir/amd64-unicode" ]]; then
      printf '!addplugindir "%s"\n' "$(to_nsis_path "$nsis_plugins_dir/amd64-unicode")"
    fi
    cat "$nsis_src"
  } > "$nsis_tmp"
}

build_nsis() {
  (
    cd "$NETBIRD_DIR/client"
    APPVER="$nsis_appver" makensis -V2 "$nsis_tmp"
  )
}

if [[ "$has_nsis_plugins" == "1" ]]; then
  write_nsis_with_plugins
  if ! build_nsis; then
    echo "[warn] NSIS plugin mode failed, retrying without plugins"
    write_nsis_without_plugins
    build_nsis
  fi
else
  write_nsis_without_plugins
  build_nsis
fi

installer_path="$NETBIRD_DIR/netbird-installer.exe"
if [[ ! -f "$installer_path" ]]; then
  echo "[error] expected installer is missing: $installer_path"
  exit 1
fi

artifact_path="$DIST_DIR/netbird_installer_${release_version}_windows_amd64.exe"
mv -f "$installer_path" "$artifact_path"

echo "[ok] windows installer created: $artifact_path"
