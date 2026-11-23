#!/usr/bin/env python3
"""Install the default and alternate site configs into two destdirs.

The installed file lists must be disjoint: the same prefix can host both
packages side by side. Any overlapping path is a failure, including shared
locale files.
"""

import os
import shutil
import subprocess
import sys
import tempfile


def run(command, **kwargs):
    result = subprocess.run(command, capture_output=True, text=True, **kwargs)
    if result.returncode != 0:
        print(f'command failed: {" ".join(command)}', file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(1)
    return result


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
    default_conf = os.path.join(source_root, 'sites', 'whatsapp.conf')
    alt_conf = os.path.join(source_root, 'tests', 'fixtures', 'alt-site.conf')
    work = tempfile.mkdtemp(prefix='webapp-disjoint-')
    try:
        builds = {}
        for name, site_conf in (('default', default_conf), ('alt', alt_conf)):
            build_dir = os.path.join(work, 'build-' + name)
            run([meson, 'setup', build_dir, source_root,
                 '--prefix=/usr', '-Dsite=' + site_conf], timeout=600)
            run([meson, 'compile', '-C', build_dir], timeout=900)
            builds[name] = build_dir

        destdirs = {}
        for name, build_dir in builds.items():
            destdir = os.path.join(work, 'dest-' + name)
            env = dict(os.environ, DESTDIR=destdir)
            run([meson, 'install', '-C', build_dir, '--no-rebuild'],
                env=env, timeout=600)
            destdirs[name] = destdir

        default_files = installed_files(destdirs['default'])
        alt_files = installed_files(destdirs['alt'])
        overlap = sorted(default_files & alt_files)

        if overlap:
            print('installed files overlap between the two site builds:',
                  file=sys.stderr)
            for path in overlap:
                print('  ' + path, file=sys.stderr)
            return 1

        expected = {
            'usr/bin/whatsv',
            'usr/share/applications/com.github.sfesenko.whatsv.desktop',
            'usr/share/glib-2.0/schemas/com.github.sfesenko.whatsv.gschema.xml',
            'usr/share/icons/hicolor/scalable/apps/com.github.sfesenko.whatsv.svg',
        }
        missing = sorted(expected - default_files)
        if missing:
            print('default install is missing expected files:', file=sys.stderr)
            for path in missing:
                print('  ' + path, file=sys.stderr)
            return 1
        expected_alt = {
            'usr/bin/altclient',
            'usr/share/applications/com.github.sfesenko.altclient.desktop',
        }
        missing = sorted(expected_alt - alt_files)
        if missing:
            print('alternate install is missing expected files:', file=sys.stderr)
            for path in missing:
                print('  ' + path, file=sys.stderr)
            return 1

        print(f'default install: {len(default_files)} files, '
              f'alternate install: {len(alt_files)} files, 0 shared paths')
        print('executables: usr/bin/whatsv and usr/bin/altclient')
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
