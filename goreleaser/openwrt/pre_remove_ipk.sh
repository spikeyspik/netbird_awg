#!/bin/sh
set -u

action="${1:-remove}"

# Skip service management when removing from an offline rootfs image.
if [ -n "${IPKG_INSTROOT:-}" ]; then
  exit 0
fi

if [ ! -x /etc/init.d/netbird ]; then
  exit 0
fi

case "$action" in
  upgrade)
    /etc/init.d/netbird stop >/dev/null 2>&1 || true
    ;;
  *)
    /etc/init.d/netbird stop >/dev/null 2>&1 || true
    /etc/init.d/netbird disable >/dev/null 2>&1 || true
    ;;
esac

exit 0
