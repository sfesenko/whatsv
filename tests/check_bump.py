#!/usr/bin/env python3
"""Exercise scripts/bump.py in a throwaway git repository.

Covers the version rewrite, AppStream/POT updates, tag creation, and the
release commit being limited to release files even when other changes are
already staged.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile


def run(command, cwd, **kwargs):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            timeout=60, **kwargs)
    if result.returncode != 0:
        print(f'command failed: {" ".join(command)}', file=sys.stderr)
        print(result.stdout, file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        raise SystemExit(1)
    return result


def copy_file(source_root, relative, destination_root):
    destination = os.path.join(destination_root, relative)
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.copy2(os.path.join(source_root, relative), destination)


def main(argv):
    if len(argv) != 2:
        print('usage: check_bump.py SOURCE_ROOT', file=sys.stderr)
        return 2

    source_root = argv[1]
    work = tempfile.mkdtemp(prefix='webapp-bump-')
    try:
        for relative in ('meson.build', 'data/app.metainfo.xml.in',
                         'po/en.po', 'scripts/bump.py'):
            copy_file(source_root, relative, work)

        run(['git', 'init', '-q'], work)
        run(['git', 'config', 'user.email', 'test@example.invalid'], work)
        run(['git', 'config', 'user.name', 'Test'], work)
        run(['git', 'add', '-A'], work)
        run(['git', 'commit', '-qm', 'initial'], work)

        meson_text = open(os.path.join(work, 'meson.build'), encoding='utf-8').read()
        match = re.search(r"version:\s*'(\d+)\.(\d+)\.(\d+)'", meson_text)
        if not match:
            print('cannot find project version in meson.build', file=sys.stderr)
            return 1
        major, minor, patch = (int(part) for part in match.groups())
        old_version = f'{major}.{minor}.{patch}'
        new_version = f'{major}.{minor}.{patch + 1}'

        # Keep an unrelated change staged; --tag must not commit it.
        with open(os.path.join(work, 'unrelated.txt'), 'w', encoding='utf-8') as file:
            file.write('keep me staged\n')
        run(['git', 'add', 'unrelated.txt'], work)

        bumped = run([sys.executable, 'scripts/bump.py', '--patch', '--tag'], work)
        for expected in (f'{old_version} -> {new_version}', f'tagged v{new_version}'):
            if expected not in bumped.stdout:
                print(f'missing output: {expected}', file=sys.stderr)
                return 1

        meson_text = open(os.path.join(work, 'meson.build'), encoding='utf-8').read()
        if f"version: '{new_version}'" not in meson_text:
            print('meson.build version was not updated', file=sys.stderr)
            return 1

        metainfo = open(os.path.join(work, 'data/app.metainfo.xml.in'),
                        encoding='utf-8').read()
        if f'version="{new_version}"' not in metainfo:
            print('metainfo release was not added', file=sys.stderr)
            return 1

        po_text = open(os.path.join(work, 'po/en.po'), encoding='utf-8').read()
        if f'Project-Id-Version: WebApp {new_version}' not in po_text:
            print('po/en.po version was not updated', file=sys.stderr)
            return 1

        touched = run(['git', 'show', '--pretty=format:', '--name-only', 'HEAD'],
                      work).stdout.split()
        expected_files = {'meson.build', 'data/app.metainfo.xml.in', 'po/en.po'}
        if set(touched) != expected_files:
            print(f'release commit touched {touched}, expected {sorted(expected_files)}',
                  file=sys.stderr)
            return 1

        staged = run(['git', 'status', '--porcelain'], work).stdout
        if 'A  unrelated.txt' not in staged:
            print('unrelated staged file was committed or unstaged', file=sys.stderr)
            return 1

        tags = run(['git', 'tag', '--list'], work).stdout.split()
        if f'v{new_version}' not in tags:
            print('release tag was not created', file=sys.stderr)
            return 1

        # The no-argument mode must report the same date-based pkgver that
        # misc/PKGBUILD derives from the last commit.
        status = run([sys.executable, 'scripts/bump.py'], work)
        commit_date = run(['git', 'log', '-1', '--format=%cs'], work).stdout.strip()
        expected_pkgver = commit_date.replace('-', '.')
        expected_line = f'PKGBUILD pkgver: {expected_pkgver}'
        if expected_line not in status.stdout:
            print(f'missing output: {expected_line}', file=sys.stderr)
            return 1

        print(f'bump.py: {new_version}, tag, commit contents and pkgver output are correct')
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
