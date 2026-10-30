# Shell syntax of the build scripts.
fast:
    bash -n scripts/*.sh
    sh -n rootfs/usr/local/sbin/station-privileged

# Build the image into dist/.
image:
    scripts/build-image.sh
