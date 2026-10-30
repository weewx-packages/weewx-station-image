# WeeWX Station (Davis RTL, Ecowitt)

A ready-to-flash Raspberry Pi image for a WeeWX weather station. You flash a card,
open a web page and set everything up there: your station, sensors, extensions,
uploads and backups. It needs no terminal.

It works with Davis Vantage Pro, Pro2 and Vue stations through an RTL-SDR dongle,
without a Davis console, and with Ecowitt consoles and gateways. The weather pages
use the Belchertown skin.

The image is Raspberry Pi OS Lite with [WeeWX](https://weewx.com/). Everything else
comes from the [WeeWX packages catalog](https://github.com/weewx-packages/catalog),
so it updates from there: the [rtldavis](https://github.com/weewx-packages/weewx-rtldavis)
and [ecowittcustom](https://github.com/weewx-packages/weewx-ecowittcustom) drivers,
[Belchertown](https://github.com/weewx-packages/weewx-belchertown), the
[package manager](https://github.com/weewx-packages/weewx-package-manager) and the
[administration](https://github.com/weewx-packages/weewx-station-admin). It is not
an official Raspberry Pi OS release.

## Requirements

- Raspberry Pi 3, 4 or 5.
- A microSD card of 8 GB or more.
- A network with internet access. The Raspberry Pi has no battery clock, and WeeWX
  starts only once it has the correct time.
- For a Davis station: an RTL-SDR dongle with an antenna for your band, 868 MHz in
  Europe, 915 MHz in North America, 921 MHz in New Zealand. You need the band and
  the ISS channel, which the console shows.
- For an Ecowitt station: a console or gateway with **Customized** server upload.

## Installation

1. Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/) 2.0 or newer.
   Under **App Options**, set the content repository to
   `https://github.com/weewx-packages/weewx-station-image/releases/latest/download/os-list.json`.
2. Choose your Raspberry Pi and **WeeWX Station (Davis RTL, Ecowitt)**, then your card.
3. Imager offers to set the Wi-Fi network, a user and SSH. Set them here if you use
   Wi-Fi. With an Ethernet cable you can skip them.
4. Put the card in the Raspberry Pi, plug in the dongle if you have one, and power
   it on. The first start takes a few minutes.

## Setting up the station

Open <http://weewx-station.local/> in a browser on the same network. If `.local`
names do not work on your computer, use the IP address your router shows.

There is no default password. On the first visit the page asks you to choose one.
Then the **Station** page asks for your kind of station, its name, position, altitude,
time zone and units. **Save and start** starts WeeWX, and the **Status** page shows what
the receiver is doing.

For an Ecowitt station, enter the address and port shown on the **Station** page into
WS View Plus, under **Weather Services**, **Customized**.

The first weather report appears about five minutes after the first readings. From
then on the address above shows the weather pages, and the administration is at
`/admin/`. It answers only from your local network.

## Forgotten password

Turn the Raspberry Pi off and put the card in a computer. Create an empty file named
`reset-admin-password` on the partition called `bootfs`. Put the card back and start
the Raspberry Pi. The page then asks for a new password. Settings and data stay.

## Limitations

- The image has been tested on a Raspberry Pi 4, with stand-ins for the dongle and
  for the Ecowitt console. It has not been tested with a real dongle and a real ISS,
  or with a real Ecowitt console.
- Raspberry Pi 3 and 5 are untested on real hardware. The Raspberry Pi 3 has slower
  cores: the Davis receiver takes about a third of one Raspberry Pi 4 core during its
  frequency search, so the search can take longer there.
- Raspberry Pi Zero 2 W is not supported, although Imager offers the image for it. It
  has 512 MB of memory and slower cores than a Raspberry Pi 3.
- Without internet access WeeWX does not start, because it waits for the time.
- Wi-Fi can be set only in Imager.
- The first visitor chooses the password, so set it soon after the first start.
- The administration uses plain HTTP, and the Ecowitt upload has no password. Keep the
  station on a network you trust.
- Belchertown loads its charts from a public server, so viewers need internet access.

## Development

```sh
just fast          # shell syntax of the build scripts
just image         # build the image into dist/
```

`just image` needs Docker with privileged containers. On a machine that is not ARM it
also needs arm64 emulation:

```sh
docker run --rm --privileged tonistiigi/binfmt --install arm64
```

`image.env` pins every input. `scripts/boot-test.sh` boots a built image in QEMU.
`tests/standin/` holds a replacement for librtlsdr that plays a simulated ISS, for
testing a whole station on a Raspberry Pi without a dongle.

## License

Copyright (c) 2026 Manuel Hilgert. The files of this repository are under the GNU
General Public License, version 3 or later.

The image contains software under its own licenses. Each release lists the exact
packages with their versions. The sources are at <https://www.debian.org/distrib/packages>,
<https://archive.raspberrypi.com/debian/> and in the repositories named above.

Raspberry Pi is a trademark of Raspberry Pi Ltd. This project is not affiliated with
or endorsed by Raspberry Pi Ltd.
