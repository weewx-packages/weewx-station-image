#!/usr/bin/python3
# Copyright (c) 2026 Manuel Hilgert <hilman2@gmail.com>
"""Decide what the image workflow builds, and print it as lines for GITHUB_OUTPUT.

Usage: plan.py release|beta|current

- release: the newest stable WeeWX, if image.env pins an older one. Its image is
  published.
- beta: the newest WeeWX beta, if it is newer than the pinned WeeWX. Its image is
  only tested.
- current: image.env as it is. Its image is only tested.

The output has the keys build and release (true or false), weewx_version,
weewx_deb_url, image_version and reason.
"""

import os
import re
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APT_INDEX = 'https://weewx.com/apt/python3/dists/buster/main/binary-all/Packages'
BETA_FOLDER = 'https://weewx.com/downloads/development_versions/'
# WeeWX numbers its releases like 5.5.2 and its betas like 5.6.0b1. The Debian
# package adds a revision, as in 5.6.0b1-1.
VERSION = re.compile(r'^(\d+)\.(\d+)\.(\d+)(?:(a|b|rc)(\d+))?$')
PRE_RANK = {'a': 0, 'b': 1, 'rc': 2, None: 3}


def read_env(path):
    """Return the assignments of image.env.

    Args:
        path (str): The file.

    Returns:
        dict: Maps each name to its value, without quotes.
    """
    values = {}
    with open(path, encoding='utf-8') as stream:
        for line in stream:
            name, sep, value = line.strip().partition('=')
            if sep and not name.startswith('#'):
                values[name] = value.strip('"')
    return values


def fetch(url):
    """Return the text at a URL.

    Args:
        url (str): The URL.

    Returns:
        str: The body.
    """
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode('utf-8')


def sort_key(debian_version):
    """Return a key that orders Debian versions of WeeWX by PEP 440.

    dpkg puts 5.6.0b1 after 5.6.0, so its own order would take an old beta for
    newer than the release that followed it.

    Args:
        debian_version (str): A version such as '5.6.0b1-1'.

    Returns:
        tuple|None: The key, or None if the version has another form.
    """
    upstream, _, revision = debian_version.rpartition('-')
    match = VERSION.match(upstream)
    if not match or not revision.isdigit():
        return None
    major, minor, patch, pre, number = match.groups()
    return (int(major), int(minor), int(patch), PRE_RANK[pre], int(number or 0),
            int(revision))


def newest(versions):
    """Return the newest of several Debian versions of WeeWX.

    Args:
        versions (Iterable[str]): The versions. Those of another form are skipped.

    Returns:
        str|None: The newest, or None if there is none.
    """
    known = [version for version in versions if sort_key(version)]
    return max(known, key=sort_key) if known else None


def stable_versions():
    """Return the versions of WeeWX in the apt repository, which holds no betas.

    Returns:
        list[str]: Debian versions.
    """
    return re.findall(r'^Version: (\S+)$', fetch(APT_INDEX), re.MULTILINE)


def beta_packages():
    """Return the Debian packages in the folder of WeeWX development versions.

    Returns:
        dict: Maps each Debian version to the URL of its package file.
    """
    names = re.findall(r'href="(python3-weewx_([^_"]+)_all\.deb)"', fetch(BETA_FOLDER))
    return {version: BETA_FOLDER + name for name, version in names}


def next_image_version(version):
    """Return the version the next published image gets.

    Args:
        version (str): IMAGE_VERSION from image.env.

    Returns:
        str: The same version if it has no tag yet, else the next one: 0.1.0a2
            becomes 0.1.0a3, and 0.1.0 becomes 0.1.1.
    """
    tags = subprocess.run(['git', '-C', ROOT, 'tag', '--list', 'v' + version],
                          check=True, capture_output=True, text=True).stdout.split()
    if not tags:
        return version
    match = re.match(r'^(\d+\.\d+\.)(\d+)(?:(a|b|rc)(\d+))?$', version)
    if not match:
        raise ValueError('IMAGE_VERSION %s has an unexpected form.' % version)
    head, patch, pre, number = match.groups()
    if pre:
        return '%s%s%s%d' % (head, patch, pre, int(number) + 1)
    return '%s%d' % (head, int(patch) + 1)


def plan(lane, env):
    """Decide what the workflow builds.

    Args:
        lane (str): 'release', 'beta' or 'current'.
        env (dict): The assignments of image.env.

    Returns:
        dict: The output keys and their values.
    """
    pinned = env['WEEWX_VERSION']
    pinned_key = sort_key(pinned)
    if pinned_key is None:
        raise ValueError('WEEWX_VERSION %s has an unexpected form.' % pinned)
    result = dict(build='false', release='false', weewx_version=pinned, weewx_deb_url='',
                  image_version=env['IMAGE_VERSION'])
    if lane == 'current':
        result.update(build='true', reason='Test image.env as it is, with WeeWX %s.' % pinned)
    elif lane == 'release':
        stable = newest(stable_versions())
        if stable and sort_key(stable) > pinned_key:
            result.update(build='true', release='true', weewx_version=stable,
                          image_version=next_image_version(env['IMAGE_VERSION']),
                          reason='WeeWX %s is out, the image has %s.' % (stable, pinned))
        else:
            result.update(reason='The image has the newest WeeWX, %s.' % pinned)
    elif lane == 'beta':
        packages = beta_packages()
        beta = newest(packages)
        if beta and sort_key(beta) > pinned_key:
            result.update(build='true', weewx_version=beta, weewx_deb_url=packages[beta],
                          reason='Test the WeeWX beta %s.' % beta)
        else:
            result.update(reason='No WeeWX beta is newer than %s.' % pinned)
    else:
        raise ValueError('Unknown lane: %s' % lane)
    return result


def main():
    env = read_env(os.path.join(ROOT, 'image.env'))
    for name, value in plan(sys.argv[1], env).items():
        print('%s=%s' % (name, value))


if __name__ == '__main__':
    main()
