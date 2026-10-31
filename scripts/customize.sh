#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Install the station into the image. Runs inside the arm64 chroot.
set -euo pipefail
source /tmp/image.env
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
config=/etc/weewx/weewx.conf

# The chroot must not start anything: services belong to the first real boot.
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

# WeeWX reads these answers while its package installs. The location shows up
# only until the administration replaces it.
debconf-set-selections <<SELECTIONS
weewx weewx/location string WeeWX station
weewx weewx/latlon string 0, 0
weewx weewx/altitude string 0, meter
weewx weewx/units select metricwx
weewx weewx/station_type select Simulator
SELECTIONS

apt-get update
apt-get install -y --no-install-recommends \
    nginx python3-numpy python3-packaging rtl-sdr unattended-upgrades

# WeeWX and Belchertown format dates and numbers through the system's locales,
# and the base image has only en_GB. Generate one for each language Belchertown
# has a translation in, so that a station can use it without a terminal.
sed -Ei 's/^# *((de_DE|fr_FR|it_IT|ca_ES)\.UTF-8 UTF-8)$/\1/' /etc/locale.gen
locale-gen

# The WeeWX package looks for this directory to decide whether systemd runs. In
# a chroot it would otherwise install an init script, which lacks the unit's
# dependency on the time.
mkdir /run/systemd/system
apt-get install -y --no-install-recommends "weewx=$WEEWX_VERSION"
rmdir /run/systemd/system
test -f /usr/lib/systemd/system/weewx.service

# Everything below comes from the catalog, so `station-packages update` and the
# page find its source. The manager installs itself from a temporary copy: only
# then does it know the bytes of its own files, and later updates need no answers.
curl -fsSL -o /tmp/manager.tar.gz "$MANAGER_URL"
echo "$MANAGER_SHA256  /tmp/manager.tar.gz" | sha256sum -c --quiet -
mkdir /tmp/manager
tar -xzf /tmp/manager.tar.gz -C /tmp/manager --strip-components=1
rm /tmp/manager.tar.gz
bootstrap() {
    PYTHONPATH=/tmp/manager/bin:/usr/share/weewx python3 -m user.packages "$@" --config "$config"
}
bootstrap repo add packages "$CATALOG_URL" --yes
bootstrap install package-manager --repo packages --pre --version "$MANAGER_VERSION" --yes
rm -rf /tmp/manager
station-packages install rtldavis --repo packages --version "$RTLDAVIS_VERSION" --yes
station-packages install ecowittcustom --repo packages --version "$ECOWITT_VERSION" --yes
station-packages install belchertown --repo packages --version "$BELCHERTOWN_VERSION" --yes
station-packages install station-admin --repo packages --pre --version "$ADMIN_VERSION" --yes

# Belchertown is the start page. Its installer points it at a directory of its
# own, and Seasons would write into the same place.
python3 - "$config" <<'PYTHON'
import sys
import configobj
config = configobj.ConfigObj(sys.argv[1], encoding='utf-8', interpolation=False)
report = config['StdReport']
report['Belchertown']['HTML_ROOT'] = '/var/www/html/weewx'
report['Belchertown']['enable'] = 'true'
report['SeasonsReport']['HTML_ROOT'] = '/var/www/html/weewx/seasons'
report['SeasonsReport']['enable'] = 'false'
config.write()
PYTHON

weectl station reconfigure --config "$config" --driver=user.rtldavis --no-prompt --no-backup

# Without a working clock WeeWX would stamp records wrongly: the driver gives
# no time and most Raspberry Pis have no battery clock.
systemctl enable systemd-time-wait-sync.service

# The dongle, and the log on the status page of the administration.
usermod -aG plugdev,systemd-journal weewx
chown -R weewx:weewx /etc/weewx /var/www/html/weewx /var/lib/weewx
chmod 440 /etc/sudoers.d/station
visudo -cq

# WeeWX stays off until the administration has the station's settings.
systemctl disable weewx.service
systemctl enable station-admin.service station-admin-reset.service nginx.service

rm -f /etc/nginx/sites-enabled/default
ln -s ../sites-available/station /etc/nginx/sites-enabled/station

echo "$IMAGE_HOSTNAME" > /etc/hostname
sed -i "s/raspberrypi/$IMAGE_HOSTNAME/" /etc/hosts
echo "$IMAGE_NAME $IMAGE_VERSION" > /etc/station-release

apt-get clean
rm -rf /var/lib/apt/lists/* /usr/sbin/policy-rc.d /root/.bash_history
find /var/log -type f -delete
