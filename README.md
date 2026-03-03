# Patched NetBird with AmneziaWG

This repository automates building and releasing an **AWG-flavored NetBird distribution**.

This project started as a quick prototype that was hard to maintain, update, and build manually. Most of it was built in
one weekend, so treat it as a practical side project rather than a polished one. The key goal is simple: it works.

## What This Repository Produces

- Linux binaries (`amd64`, `arm64`)
- Linux packages (`.deb`, `.rpm`, Arch Linux `.pkg.tar.zst`)
- Windows installer (`.exe`)
- macOS packages (`.pkg` for `amd64` and `arm64`)
- Docker images:
  - [spikeyspik/netbird_awg](https://hub.docker.com/r/spikeyspik/netbird_awg/)
  - [spikeyspik/netbird_awg_management](https://hub.docker.com/r/spikeyspik/netbird_awg_management/)
  - [spikeyspik/netbird_awg_server](https://hub.docker.com/r/spikeyspik/netbird_awg_server/)

## How to Use

1. Install and configure a self-hosted NetBird deployment (follow the official NetBird docs).
2. Replace either the `management` or `netbird-server` Docker container image with one of the images above.
3. Update all peers to patched client versions.
4. Configure AmneziaWG values. Leave them empty if you want to use vanilla WireGuard.

```dotenv
# amnezia
NETBIRD_AMNEZIA_JC=
NETBIRD_AMNEZIA_JMIN=
NETBIRD_AMNEZIA_JMAX=
NETBIRD_AMNEZIA_S1=
NETBIRD_AMNEZIA_S2=
NETBIRD_AMNEZIA_H1=
NETBIRD_AMNEZIA_H2=
NETBIRD_AMNEZIA_H3=
NETBIRD_AMNEZIA_H4=
NETBIRD_AMNEZIA_I1=
NETBIRD_AMNEZIA_I2=
NETBIRD_AMNEZIA_I3=
NETBIRD_AMNEZIA_I4=
NETBIRD_AMNEZIA_I5=
```

## Good to Know

- The patched version is backward-compatible unless you enable AmneziaWG-specific settings.
- AmneziaWG settings are instance-wide.
- In theory, patched and unpatched clients can be used simultaneously in one instance, but each client can use either
  AmneziaWG or
  vanilla WireGuard, not both.
- This is a side project. Updates may lag behind official NetBird releases. Bugs may present.
- Auto-update works.
- Mobile clients are not supported.
- PRs are always welcome.
