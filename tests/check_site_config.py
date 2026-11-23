#!/usr/bin/env python3
"""Check the constants generated from a site config file.

The site config is parsed here independently of the Meson parser, so a
parser defect cannot silently satisfy its own expectations.
"""

import re
import sys

DEFINE_RE = re.compile(r'^#define\s+(\w+)\s+(.*?)\s*$')

REQUIRED_KEYS = ('app_id', 'app_name', 'start_url', 'icon', 'icon_symbolic')


def read_defines(path):
    defines = {}
    with open(path, encoding='utf-8') as config_h:
        for line in config_h:
            match = DEFINE_RE.match(line)
            if not match:
                continue
            value = match.group(2)
            if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
                value = value[1:-1]
            defines[match.group(1)] = value
    return defines


def bool_define(keys, key, default='true'):
    return 'TRUE' if keys.get(key, default).strip().lower() == 'true' else 'FALSE'


def parse_site_config(path):
    keys = {}
    hosts = []
    with open(path, encoding='utf-8') as site_file:
        for line in site_file:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            key, _, value = line.partition('=')
            key = key.strip()
            value = value.strip()
            if key == 'host':
                hosts.append(value)
            else:
                keys[key] = value
    return keys, hosts


def main(argv):
    if len(argv) != 3:
        print('usage: check_site_config.py CONFIG_H SITE_CONF', file=sys.stderr)
        return 2

    config_h, site_conf = argv[1:]
    defines = read_defines(config_h)
    keys, hosts = parse_site_config(site_conf)

    for key in REQUIRED_KEYS:
        if not keys.get(key, '').strip():
            print(f'{key}: required key missing or empty in {site_conf}', file=sys.stderr)
            return 1
    if not hosts or not any(host.strip() for host in hosts):
        print(f'host: required key missing or empty in {site_conf}', file=sys.stderr)
        return 1

    try:
        app_id = keys['app_id']
        exec_name = keys.get('exec_name', '').strip() or app_id.split('.')[-1]
        expected = {
            'APP_ID': app_id,
            'APP_NAME': keys['app_name'],
            'SITE_START_URL': keys['start_url'],
            'SITE_HOSTS': ','.join(hosts),
            'APP_EXEC': exec_name,
            'APP_ID_PATH': app_id.replace('.', '/'),
            'GETTEXT_PACKAGE': app_id,
            'PERSIST_COOKIES': bool_define(keys, 'persist_cookies'),
            'EPHEMERAL': bool_define(keys, 'ephemeral', 'false'),
        }
    except KeyError as missing:
        print(f'{missing}: required key missing from {site_conf}', file=sys.stderr)
        return 1

    for key, value in expected.items():
        actual = defines.get(key)
        if actual != value:
            print(f'{key}: expected {value!r}, got {actual!r}', file=sys.stderr)
            return 1

    print('site config constants are correct')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
