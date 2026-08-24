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

test('unit: Whatsv.Utils', test_whatsv,
  protocol: 'tap',
)
