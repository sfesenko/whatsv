project('webapp', ['c', 'vala'],
          version: '0.2.0',
    meson_version: '>= 1.0.0',
  default_options: [ 'warning_level=2', 'werror=false', ],
)

i18n = import('i18n')
fs = import('fs')
gnome = import('gnome')
valac = meson.get_compiler('vala')


srcdir = meson.project_source_root() / 'src'

# Site config: a flat key=value file selected with -Dsite=<path>.
site_path = get_option('site')
if not fs.is_absolute(site_path)
  site_path = meson.project_source_root() / site_path
endif

site = {}
site_hosts_list = []
foreach line : fs.read(site_path).split('\n')
  line = line.strip()
  if line == '' or line.startswith('#')
    continue
  endif
  # Meson has no maxsplit or slices, so rebuild the value after the first '='.
  parts = line.split('=')
  key = parts[0].strip()
  value_parts = []
  part_index = 0
  foreach part : parts
    if part_index > 0
      value_parts += [part]
    endif
    part_index += 1
  endforeach
  value = '='.join(value_parts).strip()
  if key == 'host'
    site_hosts_list += [value]
  else
    site += {key: value}
  endif
endforeach

foreach key : ['app_id', 'app_name', 'start_url']
  if not site.has_key(key)
    error('Site config @0@ is missing required key "@1@"'.format(site_path, key))
  endif
endforeach

if site_hosts_list.length() == 0
  error('Site config @0@ must define at least one "host" key'.format(site_path))
endif

app_id = site.get('app_id')
app_name = site.get('app_name')
site_start_url = site.get('start_url')
site_hosts = ','.join(site_hosts_list)
app_id_parts = app_id.split('.')
app_exec = app_id_parts[app_id_parts.length() - 1]
app_id_path = '/'.join(app_id_parts)
site_icon = site.get('icon', '')
site_icon_symbolic = site.get('icon_symbolic', '')
if site_icon != '' and not fs.is_absolute(site_icon)
  site_icon = meson.project_source_root() / site_icon
endif
if site_icon_symbolic != '' and not fs.is_absolute(site_icon_symbolic)
  site_icon_symbolic = meson.project_source_root() / site_icon_symbolic
endif
data_dir_root = site.get('data_dir', '')
cache_dir_root = site.get('cache_dir', '')
ephemeral = site.get('ephemeral', 'false') == 'true'

config = configuration_data()
config.set_quoted('PACKAGE_VERSION', meson.project_version ())
config.set_quoted('GETTEXT_PACKAGE', meson.project_name())
config.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))
config.set_quoted('APP_ID', app_id)
config.set_quoted('APP_NAME', app_name)
config.set_quoted('APP_EXEC', app_exec)
config.set_quoted('APP_ID_PATH', app_id_path)
config.set_quoted('SITE_START_URL', site_start_url)
config.set_quoted('SITE_HOSTS', site_hosts)
config.set_quoted('DATA_DIR_ROOT', data_dir_root)
config.set_quoted('CACHE_DIR_ROOT', cache_dir_root)
config.set('EPHEMERAL', ephemeral ? 'TRUE' : 'FALSE')
config_h = configure_file(output: 'config.h', configuration: config)

config_dep = valac.find_library ('config', dirs: srcdir)
config_inc = include_directories('.')

add_project_arguments('-DGETTEXT_PACKAGE="' + meson.project_name () + '"', language: 'c')


subdir('data')
subdir('src')
subdir('po')
subdir('tests')

# Version bump helpers: meson compile -C build bump-patch / bump-minor / bump-major
run_target('bump-patch', command: [find_program('python3'), files('scripts/bump.py'), '--patch'])
run_target('bump-minor', command: [find_program('python3'), files('scripts/bump.py'), '--minor'])
run_target('bump-major', command: [find_program('python3'), files('scripts/bump.py'), '--major'])

gnome.post_install(
     glib_compile_schemas: true,
    gtk_update_icon_cache: true,
  update_desktop_database: true,
)
