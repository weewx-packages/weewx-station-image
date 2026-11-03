# weewx-station-image

Recipe for the Raspberry Pi image "WeeWX Station (Davis RTL, Ecowitt)": Raspberry Pi
OS Lite plus WeeWX. Drivers, skin, package manager and administration come from the
catalog, so they update like any extension. Only what the system needs stays here:
nginx, the services and the privileged helper.

## Status

Alpha (before 1.0): smoke tests only, no backward compatibility.

## Checks

- `just fast`: shell syntax and Python compile, under 1 s. `just smoke` runs
  `scripts/smoke-test.sh`.
- `just image`: build into `dist/`, about 6 minutes. Needs Docker and, off ARM,
  arm64 emulation. The catalog must hold every version in `image.env`.
- `scripts/boot-test.sh`: boot a built image in QEMU as a Raspberry Pi 3, with SSH on
  localhost:2222 and HTTP on localhost:8080. It skips the watchdog and the partition
  resize, which QEMU cannot run, so neither is covered there.
- `scripts/smoke-test.sh`: the same boot, then a simulated station set up through the
  administration's API, until the first weather page. About 4 minutes locally.
- Workflow `Image` (`.github/workflows/image.yml`): lanes `release` (daily, publishes
  only for a new stable WeeWX), `beta` (Mondays, test only) and `current` (manual,
  test only). `scripts/plan.py` decides; it reads the WeeWX apt index and
  <https://weewx.com/downloads/development_versions/>. The release job commits
  `WEEWX_VERSION` and `IMAGE_VERSION` straight to `main` and tags it. New extension
  releases never build an image, because stations get them from the catalog.

Hardware claims stay separate from simulated tests. `tests/standin/` replaces
librtlsdr and proves timing and the whole WeeWX path, not radio reception.

## Structure

- `image.env`: all pinned inputs.
- `scripts/assemble.sh`: mount, chroot, compress. `scripts/customize.sh` runs in the
  arm64 chroot.
- `rootfs/`: files copied into the image as they are.
- `rootfs/usr/local/sbin/station-privileged`: the only root actions of the
  administration. Every argument is checked there.

## Conventions

The name must keep "Davis RTL"; "Raspberry Pi" appears only as "for Raspberry Pi",
with the trademark note in the README. New features belong in the catalog packages,
not in this image, or they never reach installed stations. For that reason the image
holds only the rtldavis and ecowittcustom drivers. The administration installs every
other driver from the catalog when somebody chooses it. Bookworm is not a possible
base: its librtlsdr lacks the RTL-SDR Blog V4 and zeroes ARM buffers.
