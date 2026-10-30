#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Build the image in a container. It needs loop devices, so the container is
# privileged and shares the host's /dev. Off ARM, it also needs emulation of
# arm64 programs, registered once per boot with:
#   docker run --rm --privileged tonistiigi/binfmt --install arm64
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/weewx-station-image
mkdir -p "$cache" "$root/dist"
docker build -q -t weewx-station-image-tools "$root/scripts" >/dev/null
exec docker run --rm --privileged -v /dev:/dev -v "$root:/src" -v "$cache:/cache" \
    weewx-station-image-tools /src/scripts/assemble.sh
