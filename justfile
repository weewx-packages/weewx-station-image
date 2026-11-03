# Shell syntax of the build scripts, and the Python helpers compile.
fast:
    bash -n scripts/*.sh
    sh -n rootfs/usr/local/sbin/station-privileged
    python3 -m py_compile scripts/plan.py scripts/write_imager_list.py

# Build the image into dist/.
image:
    scripts/build-image.sh

# Boot the image of dist/ in QEMU and set up a simulated station, about 4 minutes.
smoke:
    scripts/smoke-test.sh
