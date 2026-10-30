#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Boot a copy of the image in an emulated Raspberry Pi 3 with a cloud-init user,
# the way Raspberry Pi Imager prepares a card, and leave SSH and the web server
# on localhost:2222 and localhost:8080. Emulation has no dongle and is slow.
#
# QEMU differs from the hardware in two places, so this run skips both: disarming
# the watchdog in the initramfs resets the emulated machine, and the first-boot
# resize of the root partition relies on firmware that QEMU does not emulate.
# Usage: boot-test.sh [IMAGE.img.xz]; stop it with docker stop station-boot.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/image.env"
image=${1:-$root/dist/$IMAGE_NAME-$IMAGE_VERSION-arm64.img.xz}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
ssh-keygen -q -t ed25519 -N '' -f "$work/key"
cp "$image" "$work/image.img.xz"
cp "$work/key.pub" "$root/dist/boot-test.pub"
cp "$work/key" "$root/dist/boot-test.key"
docker run -d --rm --name station-boot --privileged -v /dev:/dev -v "$work:/boot-test" \
    -p 127.0.0.1:2222:2222 -p 127.0.0.1:8080:8080 \
    weewx-station-image-tools bash -c '
set -e
cd /boot-test
xz -d image.img.xz
qemu-img resize -q -f raw image.img 8G
loop=$(losetup -f --show -P image.img)
mkdir -p /mnt/boot /tmp/kernel
mount ${loop}p1 /mnt/boot
cp /mnt/boot/kernel8.img /mnt/boot/initramfs8 /mnt/boot/bcm2710-rpi-3-b-plus.dtb /tmp/kernel/
cat /mnt/boot/cmdline.txt > /tmp/kernel/cmdline
{ echo "#cloud-config"; echo "users:"; echo "- name: station"; echo "  groups: users,adm,sudo"
  echo "  shell: /bin/bash"; echo "  sudo: ALL=(ALL) NOPASSWD:ALL"
  echo "  ssh_authorized_keys:"; echo "  - $(cat key.pub)"; echo "enable_ssh: true"; } > /mnt/boot/user-data
printf "network:\n  version: 2\n  ethernets:\n    usb0:\n      dhcp4: true\n" > /mnt/boot/network-config
umount /mnt/boot
losetup -d $loop
exec qemu-system-aarch64 -M raspi3b -m 1G -smp 4 \
    -kernel /tmp/kernel/kernel8.img -initrd /tmp/kernel/initramfs8 \
    -dtb /tmp/kernel/bcm2710-rpi-3-b-plus.dtb -drive file=image.img,format=raw,if=sd \
    -append "$(sed -e "s/console=serial0,115200 console=tty1/console=ttyS0,115200 8250.nr_uarts=1/" -e "s/ resize//" /tmp/kernel/cmdline) initcall_blacklist=bcm2835_wdt_driver_init modprobe.blacklist=bcm2835_wdt" \
    -device usb-net,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80 \
    -nographic -serial null -serial mon:stdio
' >/dev/null
sleep 2
docker logs -f station-boot
