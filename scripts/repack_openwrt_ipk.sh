#!/usr/bin/env bash
set -euo pipefail

DIST_DIR="${1:-}"
if [[ -z "$DIST_DIR" ]]; then
  echo "[error] usage: $0 <dist-nfpm-dir>"
  exit 1
fi

if [[ ! -d "$DIST_DIR" ]]; then
  echo "[error] dist directory not found: $DIST_DIR"
  exit 1
fi

tmp_root="$(mktemp -d "$DIST_DIR/.openwrt-ipk-tmp.XXXXXX")"
cleanup() {
  rm -rf "$tmp_root"
}
trap cleanup EXIT

rewrite_arch() {
  local src_ipk="$1"
  local target_arch="$2"
  local out_ipk="$3"
  local work_dir="$tmp_root/$target_arch"
  local control_file="$work_dir/control/control"

  rm -rf "$work_dir"
  mkdir -p "$work_dir/pkg" "$work_dir/control"

  tar -xf "$src_ipk" -C "$work_dir/pkg"

  if [[ ! -f "$work_dir/pkg/debian-binary" || ! -f "$work_dir/pkg/control.tar.gz" || ! -f "$work_dir/pkg/data.tar.gz" ]]; then
    echo "[error] unsupported ipk layout in $src_ipk"
    exit 1
  fi

  tar -xzf "$work_dir/pkg/control.tar.gz" -C "$work_dir/control"
  perl -0pi -e "s/^Architecture:\\s*.*/Architecture: ${target_arch}/m" "$control_file"
  tar -czf "$work_dir/pkg/control.tar.gz" -C "$work_dir/control" .
  tar -cf "$out_ipk" -C "$work_dir/pkg" debian-binary control.tar.gz data.tar.gz
}

map_targets() {
  local filename="$1"
  case "$filename" in
    *_linux_amd64.ipk) echo "x86_64" ;;
    *_linux_386.ipk) echo "i386_pentium4" ;;
    *_linux_arm64.ipk) echo "aarch64_generic aarch64_cortex-a53 aarch64_cortex-a72" ;;
    *_linux_armv7.ipk) echo "arm_cortex-a7_neon-vfpv4 arm_cortex-a9 arm_cortex-a15" ;;
    *_linux_mips_softfloat.ipk) echo "mips_74kc" ;;
    *_linux_mipsle_softfloat.ipk) echo "mipsel_24kc" ;;
    *) echo "" ;;
  esac
}

shopt -s nullglob
for src_ipk in "$DIST_DIR"/netbird*_linux_*.ipk; do
  src_name="$(basename "$src_ipk")"
  targets="$(map_targets "$src_name")"

  if [[ -z "$targets" ]]; then
    echo "[skip] no OpenWrt target map for $src_name"
    continue
  fi

  stem="${src_name%.ipk}"
  stem="${stem%_linux_*}"
  for target_arch in $targets; do
    out_ipk="$DIST_DIR/${stem}_linux_${target_arch}.ipk"
    rewrite_arch "$src_ipk" "$target_arch" "$out_ipk"
    echo "[ok] wrote $(basename "$out_ipk")"
  done

  rm -f "$src_ipk"
  echo "[ok] removed generic $src_name"
done
