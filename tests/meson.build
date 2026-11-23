test_utils_sources = files(
  meson.project_source_root() / 'src/utils.vala',
  meson.current_source_dir() / 'test_whatsv.vala',
)

test_deps = [
  dependency('glib-2.0'),
  dependency('gio-2.0'),
]

test_whatsv = executable('test_whatsv',
  test_utils_sources,
  dependencies: test_deps,
  install: false,
)

test('unit_whatsv_utils', test_whatsv,
  protocol: 'tap',
)

test('no-hardcoded-site', find_program('bash'),
  args: [
    files('check_no_hardcoded_site.sh'),
    meson.project_source_root() / 'src/application.vala',
    meson.project_source_root() / 'src/window.ui',
  ],
)

python3 = find_program('python3')

test('site-config', python3,
  args: [
    files('check_site_config.py'),
    config_h,
    site_path,
  ],
)
