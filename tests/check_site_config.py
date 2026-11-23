#!/usr/bin/env python3
"""Check the constants generated from a site config file."""

import re
import sys

DEFINE_RE = re.compile(r'^#define\s+(\w+)\s+"(.*)"\s*$')


def read_quoted_defines(path):
    defines = {}
    with open(path, encoding='utf-8') as config_h:
        for line in config_h:
            match = DEFINE_RE.match(line)
            if match:
                defines[match.group(1)] = match.group(2)
    return defines


def main(argv):
    if len(argv) != 6:
        print(
            'usage: check_site_config.py CONFIG_H APP_ID APP_NAME START_URL HOSTS',
            file=sys.stderr,
        )
        return 2

    config_h, app_id, app_name, start_url, hosts = argv[1:]
    defines = read_quoted_defines(config_h)
    # APP_EXEC and APP_ID_PATH are derived from the app id, so the check does
    # not have to repeat them per site.
    expected = {
        'APP_ID': app_id,
        'APP_NAME': app_name,
        'SITE_START_URL': start_url,
        'SITE_HOSTS': hosts,
        'APP_EXEC': app_id.split('.')[-1],
        'APP_ID_PATH': app_id.replace('.', '/'),
    }

    for key, value in expected.items():
        actual = defines.get(key)
        if actual != value:
            print(f'{key}: expected {value!r}, got {actual!r}', file=sys.stderr)
            return 1

    print('site config constants are correct')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
