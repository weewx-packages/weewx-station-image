#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Turn the Raspberry Pi OS Lite image into the station image. Runs as root in
# the container of build-image.sh. Output goes to dist/.
set -euo pipefail
source /src/image.env

name=$IMAGE_NAME-$IMAGE_VERSION-arm64
base=/cache/$(basename "$BASE_URL")
work=/cache/work
image=$work/$name.img
root=$work/root

[ -f "$base" ] || curl -fsSL -o "$base" "$BASE_URL"
echo "$BASE_SHA256  $base" | sha256sum -c --quiet -

rm -rf "$work"
mkdir -p "$root"
xz -dc "$base" > "$image"

# The root partition of the base image has no room for the packages. The first
# boot grows it to fill the card, so one spare GiB only has to last the build.
truncate -s +1G "$image"
echo ', +' | sfdisk --quiet --no-reread -N 2 "$image"

loop=$(losetup -f --show -P "$image")
cleanup() {
    set +e
    for mountpoint in dev/pts dev sys proc boot/firmware ''; do
        mountpoint -q "$root/$mountpoint" && umount "$root/$mountpoint"
    done
    losetup -d "$loop"
}
trap cleanup EXIT

e2fsck -pf "${loop}p2" || [ $? -le 1 ]
resize2fs -p "${loop}p2"
mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot/firmware"
mount -t proc proc "$root/proc"
mount -t sysfs sys "$root/sys"
mount --bind /dev "$root/dev"
mount --bind /dev/pts "$root/dev/pts"

cp -r --no-preserve=ownership /src/rootfs/. "$root/"
chmod 755 "$root/usr/local/sbin/"*

cp /src/image.env "$root/tmp/image.env"
cp /src/scripts/customize.sh "$root/tmp/customize.sh"
resolv=$root/etc/resolv.conf
mv "$resolv" "$resolv.image"
cp /etc/resolv.conf "$resolv"
chroot "$root" /bin/bash /tmp/customize.sh
rm "$resolv"
mv "$resolv.image" "$resolv"
rm "$root/tmp/image.env" "$root/tmp/customize.sh"

chroot "$root" dpkg-query -W -f '${Package} ${Version}\n' > "/src/dist/$name.packages.txt"

cleanup
trap - EXIT
loop=$(losetup -f --show -P "$image")
trap 'losetup -d "$loop"' EXIT
e2fsck -pf "${loop}p2" || [ $? -le 1 ]
zerofree "${loop}p2"
losetup -d "$loop"
trap - EXIT

python3 /src/scripts/write_imager_list.py "$image" "/src/dist/$name.img.xz" > "/src/dist/$name.tmp.json"
mv "/src/dist/$name.tmp.json" /src/dist/os-list.json
rm -rf "$work"
sha256sum "/src/dist/$name.img.xz" | sed 's|/src/dist/||' > "/src/dist/$name.img.xz.sha256"
chown --reference=/src/image.env /src/dist/*
ls -la /src/dist
