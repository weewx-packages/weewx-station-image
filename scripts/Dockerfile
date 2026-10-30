# Tools to assemble and boot-test the image. Nothing from here enters the image.
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl dosfstools e2fsprogs fdisk mount python3 qemu-system-arm \
    qemu-utils openssh-client xz-utils zerofree
