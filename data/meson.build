app_conf = configuration_data()
app_conf.set('APP_ID', app_id)
app_conf.set('APP_EXEC', app_exec)
app_conf.set('APP_NAME', app_name)
app_conf.set('APP_ID_PATH', app_id_path)
app_conf.set('SITE_START_URL', site_start_url)
app_conf.set('bindir', get_option('prefix') / get_option('bindir'))

desktop_in = configure_file(
         input: 'app.desktop.in',
        output: app_id + '.desktop.in',
  configuration: app_conf,
)

desktop_file = i18n.merge_file(
         input: desktop_in,
        output: app_id + '.desktop',
          type: 'desktop',
        po_dir: '../po',
       install: true,
   install_dir: get_option('datadir') / 'applications'
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

metainfo_in = configure_file(
         input: 'app.metainfo.xml.in',
        output: app_id + '.metainfo.xml.in',
  configuration: app_conf,
)

appstream_file = i18n.merge_file(
         input: metainfo_in,
        output: app_id + '.metainfo.xml',
        po_dir: '../po',
       install: true,
   install_dir: get_option('datadir') / 'metainfo'
)

appstreamcli = find_program('appstreamcli', required: false, disabler: true)
test('Validate appstream file', appstreamcli,
     args: ['validate', '--no-net', '--explain', appstream_file])

configure_file(
         input: 'app.gschema.xml.in',
        output: app_id + '.gschema.xml',
  configuration: app_conf,
      install: true,
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

compile_schemas = find_program('glib-compile-schemas', required: false, disabler: true)
test('Validate schema file',
     compile_schemas,
     args: ['--strict', '--dry-run', meson.current_build_dir()])

configure_file(
         input: 'app.service.in',
        output: app_id + '.service',
  configuration: app_conf,
      install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

subdir('icons')
