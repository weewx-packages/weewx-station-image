#!/usr/bin/python3
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
"""Compress the finished image and print the list Raspberry Pi Imager reads.

Usage: write_imager_list.py IMAGE OUTPUT.xz

The URL assumes the image is a release asset of the repository.
"""

import datetime
import hashlib
import json
import os
import subprocess
import sys

REPOSITORY = 'https://github.com/weewx-packages/weewx-station-image'


def sha256(path):
    """Return the SHA-256 of a file.

    Args:
        path (str): The file.

    Returns:
        str: Hexadecimal digest.
    """
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def main():
    image, output = sys.argv[1:3]
    extract_size = os.path.getsize(image)
    extract_sha256 = sha256(image)
    with open(output, 'wb') as stream:
        subprocess.run(['xz', '-T0', '-6', '-c', image], check=True, stdout=stream)
    version = os.path.basename(output).split('-')[-2]
    entry = dict(
        name='WeeWX Station (Davis RTL, Ecowitt) %s' % version,
        description='WeeWX weather station with web administration, for Davis wireless sensors '
                    'with an RTL-SDR dongle and for Ecowitt consoles. For Raspberry Pi 3, 4 and 5.',
        icon='https://downloads.raspberrypi.com/raspios_armhf/Raspberry_Pi_OS_(32-bit).png',
        url='%s/releases/download/v%s/%s' % (REPOSITORY, version, os.path.basename(output)),
        extract_size=extract_size,
        extract_sha256=extract_sha256,
        image_download_size=os.path.getsize(output),
        image_download_sha256=sha256(output),
        release_date=datetime.date.today().isoformat(),
        # The base image reads Imager's Wi-Fi, user and SSH settings through
        # cloud-init, so the station inherits that wizard unchanged.
        init_format='cloudinit-rpi',
        # Imager has one tag for Raspberry Pi 3 and Zero 2 W, so it offers the
        # image for both, although only the Raspberry Pi 3 is meant.
        devices=['pi5-64bit', 'pi4-64bit', 'pi3-64bit'],
    )
    json.dump(dict(imager=dict(), os_list=[entry]), sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    main()
