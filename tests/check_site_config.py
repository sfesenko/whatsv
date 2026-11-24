#!/usr/bin/env python3
"""Check constants and generated data files for one configured build.

The site config is parsed independently of the Meson parser, so a parser
defect cannot silently satisfy its own expectations. The generated desktop
entry, D-Bus service, GSchema and AppStream file are checked too.
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

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


def read_desktop(path):
    values = {}
    with open(path, encoding='utf-8') as desktop_file:
        for line in desktop_file:
            line = line.strip()
            if not line or line.startswith('#') or line.startswith('['):
                continue
            key, _, value = line.partition('=')
            values[key.strip()] = value.strip()
    return values


def check_desktop(path, keys, hosts, expected_exec):
    values = read_desktop(path)
    expected = {
        'Name': keys['app_name'],
        'Exec': expected_exec + ' %U',
        'Icon': keys['app_id'],
        'StartupWMClass': keys['app_id'],
        'DBusActivatable': 'true',
    }
    errors = []
    for key, value in expected.items():
        if values.get(key) != value:
            errors.append(f'{key}: expected {value!r}, got {values.get(key)!r}')
    return errors


def check_service(path, keys, expected_exec, prefix):
    values = {}
    with open(path, encoding='utf-8') as service_file:
        for line in service_file:
            key, _, value = line.strip().partition('=')
            values[key.strip()] = value.strip()
    expected = {
        'Name': keys['app_id'],
        'Exec': os.path.join(prefix, 'bin', expected_exec) + ' --gapplication-service',
    }
    errors = []
    for key, value in expected.items():
        if values.get(key) != value:
            errors.append(f'{key}: expected {value!r}, got {values.get(key)!r}')
    return errors


def check_schema(path, keys):
    root = ET.parse(path).getroot()
    errors = []
    if root.get('gettext-domain') != keys['app_id']:
        errors.append(
            f'gettext-domain: expected {keys["app_id"]!r}, '
            f'got {root.get("gettext-domain")!r}')
    schema = root.find('schema')
    if schema is None:
        errors.append('schema element is missing')
        return errors
    expected_path = '/' + keys['app_id'].replace('.', '/') + '/'
    if schema.get('id') != keys['app_id']:
        errors.append(f'schema id: expected {keys["app_id"]!r}, got {schema.get("id")!r}')
    if schema.get('path') != expected_path:
        errors.append(f'schema path: expected {expected_path!r}, got {schema.get("path")!r}')
    return errors


def check_metainfo(path, keys):
    root = ET.parse(path).getroot()
    errors = []
    if root.findtext('id') != keys['app_id']:
        errors.append(f'id: expected {keys["app_id"]!r}, got {root.findtext("id")!r}')
    if root.findtext('name') != keys['app_name']:
        errors.append(f'name: expected {keys["app_name"]!r}, got {root.findtext("name")!r}')

    homepage = None
    for url in root.findall('url'):
        if url.get('type') == 'homepage':
            homepage = url.text
            break
    if homepage != keys['start_url']:
        errors.append(
            f'url homepage: expected {keys["start_url"]!r}, got {homepage!r}')

    translation = root.find('translation')
    if translation is None or translation.get('type') != 'gettext' or translation.text != keys['app_id']:
        errors.append(f'translation: expected gettext domain {keys["app_id"]!r}')

    launchable = root.find('launchable')
    expected_launchable = keys['app_id'] + '.desktop'
    if launchable is None or launchable.get('type') != 'desktop-id' or launchable.text != expected_launchable:
        errors.append(f'launchable: expected {expected_launchable!r}')
    return errors


def check_generated(build_dir, keys, hosts, prefix):
    app_id = keys['app_id']
    expected_exec = keys.get('exec_name', '').strip() or app_id.split('.')[-1]
    data_dir = os.path.join(build_dir, 'data')
    checks = (
        (os.path.join(data_dir, app_id + '.desktop'),
         lambda: check_desktop(os.path.join(data_dir, app_id + '.desktop'),
                               keys, hosts, expected_exec)),
        (os.path.join(data_dir, app_id + '.service'),
         lambda: check_service(os.path.join(data_dir, app_id + '.service'),
                               keys, expected_exec, prefix)),
        (os.path.join(data_dir, app_id + '.gschema.xml'),
         lambda: check_schema(os.path.join(data_dir, app_id + '.gschema.xml'), keys)),
        (os.path.join(data_dir, app_id + '.metainfo.xml'),
         lambda: check_metainfo(os.path.join(data_dir, app_id + '.metainfo.xml'), keys)),
    )
    errors = []
    for path, check in checks:
        if not os.path.isfile(path):
            errors.append(f'missing generated file: {path}')
            continue
        errors.extend(check())
    return errors


def main(argv):
    if len(argv) != 4:
        print('usage: check_site_config.py CONFIG_H SITE_CONF BUILD_DIR',
              file=sys.stderr)
        return 2

    config_h, site_conf, build_dir = argv[1:]
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
        prefix = defines.get('LOCALEDIR', '/usr/share/locale').rsplit('/share/locale', 1)[0]
        expected = {
            'APP_ID': app_id,
            'APP_NAME': keys['app_name'],
            'SITE_START_URL': keys['start_url'],
            'SITE_HOSTS': ','.join(hosts),
            'APP_EXEC': exec_name,
            'APP_ID_PATH': app_id.replace('.', '/'),
            'GETTEXT_PACKAGE': app_id,
            'DATA_DIR_ROOT': keys.get('data_dir', '').strip(),
            'CACHE_DIR_ROOT': keys.get('cache_dir', '').strip(),
            'PERSIST_COOKIES': bool_define(keys, 'persist_cookies', 'true'),
            'EPHEMERAL': bool_define(keys, 'ephemeral', 'false'),
        }
    except KeyError as missing:
        print(f'{missing}: required key missing from {site_conf}', file=sys.stderr)
        return 1

    errors = []
    for key, value in expected.items():
        actual = defines.get(key)
        if actual != value:
            errors.append(f'{key}: expected {value!r}, got {actual!r}')

    errors.extend(check_generated(build_dir, keys, hosts, prefix))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print('site config constants and generated files are correct')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
