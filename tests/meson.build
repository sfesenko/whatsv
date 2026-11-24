test_utils_sources = files(
  meson.project_source_root() / 'src/utils.vala',
  meson.current_source_dir() / 'test_utils.vala',
)

test_deps = [
  config_dep,
  dependency('glib-2.0'),
  dependency('gio-2.0'),
]

test_utils = executable('test_utils',
  test_utils_sources,
  dependencies: test_deps,
  include_directories: config_inc,
  install: false,
)

test('unit_utils', test_utils,
  protocol: 'tap',
)

python3 = find_program('python3')
meson_bin = find_program('meson')

test('site-config', python3,
  args: [
    files('check_site_config.py'),
    config_h,
    site_path,
    meson.global_build_root(),
  ],
)

test('config-errors', python3,
  args: [
    files('check_config_errors.py'),
    meson_bin.full_path(),
    meson.project_source_root(),
    meson.current_source_dir() / 'fixtures',
  ],
  timeout: 600,
)

test('disjoint-install', python3,
  args: [
    files('check_disjoint_install.py'),
    meson_bin.full_path(),
    meson.project_source_root(),
  ],
  timeout: 1800,
)
