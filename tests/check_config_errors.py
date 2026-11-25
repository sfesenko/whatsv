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
    ('broken-no-host.conf', 'must define at least one "host" key'),
    ('broken-app-id.conf', 'has an empty segment'),
    ('broken-app-id-single.conf', 'must have at least two dot-separated segments'),
    ('broken-app-id-start.conf', 'segment "1example" in "com.1example" must start with an ASCII letter'),
    ('broken-app-id-char.conf', 'contains invalid character "!" (allowed: A-Z, a-z, 0-9, "_", "-")'),
    ('broken-start-url-uncovered.conf', 'is not covered by any "host" entry'),
    ('broken-missing-icon.conf', 'missing required key "icon"'),
    ('broken-missing-icon-file.conf', '"icon" file'),
    ('broken-missing-icon-symbolic-file.conf', '"icon_symbolic" file'),
    ('broken-empty-app-name.conf', 'has an empty required key "app_name"'),
    ('broken-empty-start-url.conf', 'has an empty required key "start_url"'),
    ('broken-exec-name.conf', '"exec_name" value "bad/name" contains invalid character'),
    ('broken-persist-cookies.conf', '"persist_cookies" must be "true" or "false"'),
    ('broken-start-url-scheme.conf', '"start_url" must use http:// or https://'),
    ('broken-relative-data-dir.conf', '"data_dir" must be an absolute path'),
    ('broken-relative-cache-dir.conf', '"cache_dir" must be an absolute path'),
    ('broken-host-single-label.conf', 'host "com" must be a fully qualified domain name'),
    ('broken-host-ipv4-fragment.conf', 'host "0.0.1" is not a valid IPv4 address'),
    ('broken-host-port.conf', 'host "example.com:443" must not include a port'),
    ('broken-host-list.conf', 'host "example.com,evil.example" must be a single hostname'),
    ('broken-host-backslash.conf', 'host "example.com\\x2c.evil.com" must not contain backslashes'),
    ('broken-host-bracket.conf', 'has an invalid IPv6 literal'),
    ('broken-host-ipv6-invalid.conf', 'has an invalid IPv6 literal'),
    ('broken-host-ipv6-short.conf', 'has an invalid IPv6 literal'),
    ('broken-host-ipv6-long.conf', 'has an invalid IPv6 literal'),
    ('broken-host-ipv6-ipv4.conf', 'has an invalid IPv6 literal'),
    ('broken-host-ipv6-group.conf', 'has an invalid IPv6 literal'),
    ('broken-start-url-backslash.conf', '"start_url" must not contain backslashes'),
    ('broken-start-url-port.conf', '"start_url" has an invalid port'),
    ('broken-data-dir-backslash.conf', '"data_dir" must not contain backslashes'),
    ('broken-app-name-formfeed.conf', '"app_name" must not contain control characters'),
    ('broken-duplicate-key.conf', 'duplicate key "app_name"'),
    ('broken-app-name-backslash.conf', '"app_name" must not contain control characters or backslashes'),
)


def run_setup(meson, source_root, site_conf, build_dir):
    return subprocess.run(
        [meson, 'setup', build_dir, source_root, '-Dsite=' + site_conf],
        capture_output=True,
        text=True,
        timeout=600,
    )


def run_compile(meson, build_dir):
    result = subprocess.run(
        [meson, 'compile', '-C', build_dir],
        capture_output=True,
        text=True,
        timeout=900,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stdout + result.stderr)
    return result


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

        valid_cases = (
            'ephemeral-site.conf',
            'true-ephemeral-site.conf',
            'xml-site.conf',
            'quotes-site.conf',
            'ipv6-site.conf',
        )
        for index, fixture in enumerate(valid_cases):
            site_conf = os.path.join(fixture_dir, fixture)
            build_dir = os.path.join(work, f'valid-{index}')
            result = run_setup(meson, source_root, site_conf, build_dir)
            if result.returncode != 0:
                failures.append(
                    f'{fixture}: meson setup failed:\n'
                    + result.stdout + result.stderr)
                continue
            try:
                run_compile(meson, build_dir)
            except RuntimeError as error:
                failures.append(f'{fixture}: compile failed:\n{error}')
                continue
            checked = subprocess.run(
                [sys.executable,
                 os.path.join(source_root, 'tests', 'check_site_config.py'),
                 os.path.join(build_dir, 'config.h'),
                 site_conf, build_dir],
                capture_output=True, text=True, timeout=60)
            if checked.returncode != 0:
                failures.append(
                    f'{fixture}: generated files/constants are wrong:\n'
                    + checked.stdout + checked.stderr)
            else:
                print(f'{fixture}: constants and generated files are correct')
            tested = subprocess.run(
                [meson, 'test', '-C', build_dir, 'unit_utils', '--print-errorlogs'],
                capture_output=True, text=True, timeout=120)
            if tested.returncode != 0:
                failures.append(
                    f'{fixture}: unit_utils failed:\n'
                    + tested.stdout + tested.stderr)
            else:
                print(f'{fixture}: unit_utils passed')
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
