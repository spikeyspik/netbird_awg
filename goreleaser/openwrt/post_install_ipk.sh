#!/bin/sh
set -u

# Skip service management when installing into an offline rootfs image.
if [ -n "${IPKG_INSTROOT:-}" ]; then
  exit 0
fi

# Keep OpenWrt behavior predictable: do not auto-enable on fresh install.
if [ -x /etc/init.d/netbird ] && /etc/init.d/netbird enabled >/dev/null 2>&1; then
  /etc/init.d/netbird restart >/dev/null 2>&1 || true
fi

exit 0
