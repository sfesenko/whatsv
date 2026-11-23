#!/usr/bin/env python3
"""Exercise site-config validation with purpose-broken configs.

Each broken fixture must make `meson setup` fail before any file is touched,
and the error must name the offending key. A valid fixture with
`persist_cookies=false` and `ephemeral=true` is configured too, so the
generated constants for that combination are checked.
"""

import os
import shutil
import subprocess
import sys
import tempfile

CASES = (
    ('broken-unknown-key.conf', 'has unknown key "bogus_key"'),
    ('broken-bool.conf', '"ephemeral" must be "true" or "false"'),
    ('broken-missing-key.conf', 'missing required key "app_name"'),
    ('broken-empty-host.conf', 'has an empty "host" value'),
    ('broken-app-id.conf', 'has an empty segment'),
    ('broken-missing-icon.conf', 'missing required key "icon"'),
    ('broken-missing-icon-file.conf', '"icon" file'),
)


def run_setup(meson, source_root, site_conf, build_dir):
    return subprocess.run(
        [meson, 'setup', build_dir, source_root, '-Dsite=' + site_conf],
        capture_output=True,
        text=True,
        timeout=600,
    )


def main(argv):
    if len(argv) != 4:
        print('usage: check_config_errors.py MESON SOURCE_ROOT FIXTURE_DIR',
              file=sys.stderr)
        return 2

    meson, source_root, fixture_dir = argv[1:]
    work = tempfile.mkdtemp(prefix='webapp-config-errors-')
    failures = []
    try:
        for index, (fixture, expected) in enumerate(CASES):
            site_conf = os.path.join(fixture_dir, fixture)
            build_dir = os.path.join(work, f'broken-{index}')
            result = run_setup(meson, source_root, site_conf, build_dir)
            output = result.stdout + result.stderr
            if result.returncode == 0:
                failures.append(f'{fixture}: meson setup unexpectedly succeeded')
            elif expected not in output:
                failures.append(
                    f'{fixture}: expected error containing {expected!r}, '
                    f'got:\n{output}')
            else:
                first = next((line for line in output.splitlines()
                              if 'ERROR:' in line), expected)
                print(f'{fixture}: rejected as expected: {first.strip()}')

        ephemeral_conf = os.path.join(fixture_dir, 'ephemeral-site.conf')
        ephemeral_build = os.path.join(work, 'ephemeral')
        result = run_setup(meson, source_root, ephemeral_conf, ephemeral_build)
        if result.returncode != 0:
            failures.append(
                'ephemeral-site.conf: meson setup failed:\n'
                + result.stdout + result.stderr)
        else:
            with open(os.path.join(ephemeral_build, 'config.h'),
                      encoding='utf-8') as config_h:
                defines = config_h.read()
            expected_defines = {
                '#define EPHEMERAL TRUE': 'EPHEMERAL TRUE',
                '#define PERSIST_COOKIES FALSE': 'PERSIST_COOKIES FALSE',
                '#define APP_EXEC "ephemeralclient"': 'APP_EXEC "ephemeralclient"',
            }
            for needle, label in expected_defines.items():
                if needle not in defines:
                    failures.append(
                        f'ephemeral-site.conf: missing {label} in config.h')
            print('ephemeral-site.conf: configured with '
                  'EPHEMERAL TRUE, PERSIST_COOKIES FALSE, '
                  'APP_EXEC "ephemeralclient"')
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f'all {len(CASES)} broken configs rejected as expected')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
