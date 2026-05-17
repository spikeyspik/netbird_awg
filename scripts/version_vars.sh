#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/.env}"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "[error] config file not found: $CONFIG_FILE" >&2
  exit 1
fi

# Load key=value pairs from config only when the variable is not already set in env.
while IFS= read -r raw_line; do
  line="${raw_line%%#*}"
  line="${line%$'\r'}"
  if [[ -z "$line" || "$line" != *=* ]]; then
    continue
  fi

  key="${line%%=*}"
  value="${line#*=}"

  key="${key//[[:space:]]/}"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"

  if [[ -z "$key" ]]; then
    continue
  fi

  if [[ -z "${!key+x}" ]]; then
    export "$key=$value"
  fi
done < "$CONFIG_FILE"

AWG_VERSION_SUFFIX="${AWG_VERSION_SUFFIX:-awg.r1}"

if [[ -n "${BASE_TAG:-}" ]]; then
  NETBIRD_BASE_TAG="$BASE_TAG"
fi

if [[ -z "${NETBIRD_BASE_TAG:-}" && -n "${NETBIRD_REF:-}" ]]; then
  NETBIRD_BASE_TAG="$NETBIRD_REF"
fi

if [[ -z "${NETBIRD_BASE_TAG:-}" ]]; then
  echo "[error] NETBIRD_BASE_TAG is empty. Set it in .env or BASE_TAG env." >&2
  exit 1
fi

NETBIRD_REF="${NETBIRD_REF:-$NETBIRD_BASE_TAG}"

if [[ "$NETBIRD_BASE_TAG" == *"$AWG_VERSION_SUFFIX"* ]]; then
  computed_release_tag="$NETBIRD_BASE_TAG"
else
  if [[ "$AWG_VERSION_SUFFIX" == [-.+]* ]]; then
    computed_release_tag="${NETBIRD_BASE_TAG}${AWG_VERSION_SUFFIX}"
  else
    computed_release_tag="${NETBIRD_BASE_TAG}-${AWG_VERSION_SUFFIX}"
  fi
fi

NETBIRD_RELEASE_TAG="${NETBIRD_RELEASE_TAG:-$computed_release_tag}"
NETBIRD_PACKAGE_VERSION="${NETBIRD_RELEASE_TAG#v}"
NETBIRD_PACKAGE_VERSION="${NETBIRD_PACKAGE_VERSION//-/.}"


if [[ -z "${ANDROID_BASE_TAG:-}" ]]; then
  echo "[error] ANDROID_BASE_TAG is empty. Set it in .env." >&2
  exit 1
fi

ANDROID_REF="${ANDROID_REF:-$ANDROID_BASE_TAG}"

export CONFIG_FILE
export NETBIRD_BASE_TAG
export NETBIRD_REF
export NETBIRD_RELEASE_TAG
export NETBIRD_PACKAGE_VERSION
export AWG_VERSION_SUFFIX
export ANDROID_BASE_TAG
export ANDROID_REF

print_key_values() {
  cat <<VARS
NETBIRD_BASE_TAG=$NETBIRD_BASE_TAG
NETBIRD_REF=$NETBIRD_REF
NETBIRD_RELEASE_TAG=$NETBIRD_RELEASE_TAG
NETBIRD_PACKAGE_VERSION=$NETBIRD_PACKAGE_VERSION
AWG_VERSION_SUFFIX=$AWG_VERSION_SUFFIX
ANDROID_BASE_TAG=$ANDROID_BASE_TAG
ANDROID_REF=$ANDROID_REF
VARS
}

case "${1:-}" in
  --print)
    print_key_values
    ;;
  --github-env)
    print_key_values
    ;;
  "")
    ;;
  *)
    echo "[error] unsupported argument: $1" >&2
    exit 1
    ;;
esac
