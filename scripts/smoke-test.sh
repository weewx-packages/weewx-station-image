#!/bin/bash
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
#
# Boot the image in QEMU, set up a simulated station through the administration
# the way a user would, and wait for the first weather page. The workflow
# publishes an image only after this passes. It proves that the image starts and
# that WeeWX, the administration and Belchertown work together, not that any
# real station or dongle does.
# Usage: smoke-test.sh [IMAGE.img.xz]
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
source "$root/image.env"
key=$root/dist/boot-test.key
log=$root/dist/boot-test.log
admin=http://localhost:8080/admin/api
cookies=$(mktemp)
# wait_for silences the commands it repeats. File descriptor 3 keeps the real
# stderr for the messages that explain a failure.
exec 3>&2

# Stopping the container also ends boot-test.sh, which then removes its copy of
# the image.
finish() {
    docker stop station-boot >/dev/null 2>&1 || true
    wait
    rm -f "$cookies"
}
trap finish EXIT
rm -f "$key"
"$root/scripts/boot-test.sh" "$@" > "$log" 2>&1 &

station() {
    ssh -q -i "$key" -p 2222 -o BatchMode=yes -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null station@localhost "$@"
}

# Called as api PATH [JSON]. The header marks the request as coming from the page.
# An error reply goes to the real stderr, so a timeout shows what the
# administration answered.
api() {
    local reply
    if ! reply=$(curl -sS --fail-with-body -b "$cookies" -c "$cookies" \
            -H 'X-Station-Admin: 1' -H 'Content-Type: application/json' \
            ${2:+--data "$2"} "$admin/$1"); then
        [ -z "$reply" ] || echo "$(date +%T) $1: $reply" >&3
        return 1
    fi
    printf '%s\n' "$reply"
}

# Called as wait_for SECONDS DESCRIPTION COMMAND... Repeats COMMAND until it
# succeeds and stops the test once SECONDS have passed.
wait_for() {
    local deadline=$((SECONDS + $1)) what=$2
    shift 2
    until "$@" >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "Timed out waiting for: $what" >&2
            tail -n 60 "$log" >&2
            exit 1
        fi
        sleep 10
    done
    echo "$what after ${SECONDS} s"
}

# Succeeds once the job of the administration is done, and stops the test if it
# failed.
job_done() {
    local state
    state=$(api "jobs/$1" | python3 -c 'import json, sys; print(json.load(sys.stdin)["state"])')
    if [ "$state" = 'failed' ]; then
        api "jobs/$1" | python3 -c 'import json, sys; print(json.load(sys.stdin)["log"])' >&3
        exit 1
    fi
    [ "$state" = 'done' ]
}

check() {
    if [ "$2" != "$3" ]; then
        echo "$1: expected '$3', found '$2'" >&2
        exit 1
    fi
    echo "$1: $2"
}

wait_for 1800 "SSH" station true
wait_for 600 "Administration" api session
check "WeeWX package" "$(station "dpkg-query -W -f '\${Version}' weewx")" "$WEEWX_VERSION"
check "Image" "$(station cat /etc/station-release)" "$IMAGE_NAME $IMAGE_VERSION"
# WeeWX stays off until the station page has its settings.
check "WeeWX before setup" "$(station systemctl is-enabled weewx || true)" disabled

api setup-password '{"password": "smoke-test-password"}' >/dev/null
job=$(api station '{"driver": "simulator", "location": "Smoke test",
    "latitude": 50.1, "longitude": 8.7, "altitude": 100, "altitude_unit": "meter",
    "timezone": "Europe/Berlin", "units": "metricwx", "language": "en_GB.UTF-8"}' |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["job"])')
wait_for 1200 "Station settings" job_done "$job"
check "WeeWX after setup" "$(station systemctl is-enabled weewx || true)" enabled

# The simulator writes a record every five minutes, and the report follows it.
wait_for 1800 "First weather page" curl -fsS -o /dev/null http://localhost:8080/index.html
check "WeeWX running" "$(station systemctl is-active weewx || true)" active
