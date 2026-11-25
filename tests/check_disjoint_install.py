#!/usr/bin/env python3
"""Install two distinct test site configs into separate destdirs.

The installed file lists must be disjoint so both packages can coexist.
Expected paths are derived from each config; no site-specific values are
hardcoded here. Each build's generated constants are also checked against its
config.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile


FIXTURES = ('alt-site.conf', 'ephemeral-site.conf')


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        print(f'command failed: {" ".join(command)}', file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(1)
    return result


def install_dirs(build_dir):
    options_path = os.path.join(build_dir, 'meson-info',
                                'intro-buildoptions.json')
    with open(options_path, encoding='utf-8') as options_file:
        options = {item['name']: item['value']
                   for item in json.load(options_file)}
    prefix = options.get('prefix', '/usr')

    def dest_path(value):
        path = value if os.path.isabs(value) else os.path.join(prefix, value)
        return path.lstrip('/')

    return {
        'bindir': dest_path(options.get('bindir', 'bin')),
        'datadir': dest_path(options.get('datadir', 'share')),
        'localedir': dest_path(options.get('localedir', 'share/locale')),
    }


def parse_config(path):
    keys = {}
    with open(path, encoding='utf-8') as config:
        for line in config:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            key, _, value = line.partition('=')
            if key != 'host':
                keys[key.strip()] = value.strip()
    return keys


def exec_name(keys):
    app_id = keys['app_id']
    return keys.get('exec_name', '').strip() or app_id.rsplit('.', 1)[-1]


def expected_files(keys, dirs):
    app_id = keys['app_id']
    bindir = dirs['bindir']
    datadir = dirs['datadir']
    return {
        f'{bindir}/{exec_name(keys)}',
        f'{datadir}/applications/{app_id}.desktop',
        f'{datadir}/glib-2.0/schemas/{app_id}.gschema.xml',
        f'{datadir}/dbus-1/services/{app_id}.service',
        f'{datadir}/metainfo/{app_id}.metainfo.xml',
        f'{datadir}/icons/hicolor/scalable/apps/{app_id}.svg',
        f'{datadir}/icons/hicolor/symbolic/apps/{app_id}-symbolic.svg',
        f'{datadir}/licenses/{app_id}/COPYING',
    }


def is_app_locale_file(path, app_id, localedir):
    prefix = localedir.rstrip('/') + '/'
    if not path.startswith(prefix):
        return False
    parts = path[len(prefix):].split('/')
    return (len(parts) == 3
            and parts[1] == 'LC_MESSAGES'
            and parts[2] == app_id + '.mo')


def installed_files(destdir):
    paths = []
    for root, _, files in os.walk(destdir):
        for name in files:
            paths.append(os.path.relpath(os.path.join(root, name), destdir))
    return set(paths)


def main(argv):
    if len(argv) != 3:
        print('usage: check_disjoint_install.py MESON SOURCE_ROOT',
              file=sys.stderr)
        return 2

    meson, source_root = argv[1:]
    config_checker = os.path.join(source_root, 'tests', 'check_site_config.py')
    work = tempfile.mkdtemp(prefix='webapp-disjoint-')
    results = []
    try:
        for index, fixture in enumerate(FIXTURES):
            site_conf = os.path.join(source_root, 'tests', 'fixtures', fixture)
            keys = parse_config(site_conf)
            build_dir = os.path.join(work, f'build-{index}')
            run([meson, 'setup', build_dir, source_root,
                 '--prefix=/usr', '-Dsite=' + site_conf], timeout=600)
            run([meson, 'compile', '-C', build_dir], timeout=900)
            dirs = install_dirs(build_dir)
            run([sys.executable, config_checker,
                 os.path.join(build_dir, 'config.h'), site_conf, build_dir],
                timeout=60)

            destdir = os.path.join(work, f'dest-{index}')
            env = dict(os.environ, DESTDIR=destdir)
            run([meson, 'install', '-C', build_dir, '--no-rebuild'],
                env=env, timeout=600)
            installed = installed_files(destdir)
            expected = expected_files(keys, dirs)
            missing = sorted(expected - installed)
            extra = sorted(path for path in installed - expected
                           if not is_app_locale_file(path, keys['app_id'], dirs['localedir']))
            if not any(is_app_locale_file(path, keys['app_id'], dirs['localedir'])
                       for path in installed):
                missing.append('usr/share/locale/*/LC_MESSAGES/'
                               + keys['app_id'] + '.mo')
            if missing or extra:
                print(f'{fixture} install differs from expected files:',
                      file=sys.stderr)
                for path in missing:
                    print('  missing: ' + path, file=sys.stderr)
                for path in extra:
                    print('  extra: ' + path, file=sys.stderr)
                return 1
            results.append((fixture, keys['app_id'], exec_name(keys), installed))

        overlap = sorted(results[0][3] & results[1][3])
        if overlap:
            print('installed files overlap between the two site builds:',
                  file=sys.stderr)
            for path in overlap:
                print('  ' + path, file=sys.stderr)
            return 1

        first, second = results
        print(f'{first[0]}: {len(first[3])} files, '
              f'{second[0]}: {len(second[3])} files, 0 shared paths')
        print('executables: '
              + ' and '.join(f'usr/bin/{result[2]}' for result in results))
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
