#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Print the notes of a release that the workflow publishes after a new WeeWX
# release. Everything comes from image.env, so the notes name what was built.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/image.env"
weewx=${WEEWX_VERSION%-*}
base_date=$(sed -E 's|.*raspios_lite_arm64-([0-9-]+)/.*|\1|' <<<"$BASE_URL")

cat <<NOTES
A ready-to-flash image for a WeeWX station with web administration. It supports Davis stations through an RTL-SDR dongle and Ecowitt consoles. Setup and the Imager repository URL are in the [README](https://github.com/weewx-packages/weewx-station-image#installation).

This image was built automatically for WeeWX $weewx. It passed a boot test in QEMU with a simulated station. It has not been tested on a Raspberry Pi or with a real station.

A running station does not need this image. It gets WeeWX $weewx with **Update the system** on the **System** page.

- Base: Raspberry Pi OS Lite trixie arm64, $base_date
- WeeWX $weewx
- From the catalog: rtldavis $RTLDAVIS_VERSION, ecowittcustom $ECOWITT_VERSION, Belchertown $BELCHERTOWN_VERSION, package-manager $MANAGER_VERSION, station-admin $ADMIN_VERSION

\`$IMAGE_NAME-$IMAGE_VERSION-arm64.packages.txt\` lists every Debian package with its version. Sources are at [Debian](https://www.debian.org/distrib/packages) and [Raspberry Pi](https://archive.raspberrypi.com/debian/).
NOTES
