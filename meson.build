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
known_keys = [
  'app_id',
  'app_name',
  'start_url',
  'host',
  'icon',
  'icon_symbolic',
  'data_dir',
  'cache_dir',
  'ephemeral',
  'persist_cookies',
  'exec_name',
]
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
  if not known_keys.contains(key)
    error('Site config @0@ has unknown key "@1@"; known keys are @2@'.format(site_path, key, ', '.join(known_keys)))
  endif
  if key == 'host'
    if value == ''
      error('Site config @0@ has an empty "host" value'.format(site_path))
    endif
    site_hosts_list += [value]
  else
    site += {key: value}
  endif
endforeach

foreach key : ['app_id', 'app_name', 'start_url', 'icon', 'icon_symbolic']
  if not site.has_key(key)
    error('Site config @0@ is missing required key "@1@"'.format(site_path, key))
  endif
  if site.get(key) == ''
    error('Site config @0@ has an empty required key "@1@"'.format(site_path, key))
  endif
endforeach

app_id = site.get('app_id')
# Meson has no regular expressions or character iteration, so the reverse-DNS
# rule is checked by hand: at least two dot-separated segments, each non-empty,
# starting with an ASCII letter and otherwise using only [A-Za-z0-9_-].
id_first_chars = 'a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U,V,W,X,Y,Z'.split(',')
id_other_chars = id_first_chars + '0,1,2,3,4,5,6,7,8,9,_,-'.split(',')
app_id_parts = app_id.split('.')
if app_id_parts.length() < 2
  error('Site config @0@: "app_id" value "@1@" must have at least two dot-separated segments (reverse-DNS form)'.format(site_path, app_id))
endif
foreach part : app_id_parts
  if part == ''
    error('Site config @0@: "app_id" value "@1@" has an empty segment'.format(site_path, app_id))
  endif
  if not id_first_chars.contains(part.substring(0, 1))
    error('Site config @0@: "app_id" segment "@1@" in "@2@" must start with an ASCII letter'.format(site_path, part, app_id))
  endif
  id_remainder = part.substring(1)
  foreach id_char : id_other_chars
    id_remainder = id_remainder.replace(id_char, '')
  endforeach
  if id_remainder != ''
    error('Site config @0@: "app_id" segment "@1@" in "@2@" contains invalid character "@3@" (allowed: A-Z, a-z, 0-9, "_", "-")'.format(site_path, part, app_id, id_remainder.substring(0, 1)))
  endif
endforeach

if site_hosts_list.length() == 0
  error('Site config @0@ must define at least one "host" key'.format(site_path))
endif

app_id = site.get('app_id')
app_name = site.get('app_name')
site_start_url = site.get('start_url')
site_hosts = ','.join(site_hosts_list)

# The start URL must be served by one of the allowed hosts, otherwise the app
# opens a blank window because navigation is refused at startup.
start_host = site_start_url.strip().to_lower()
start_scheme_parts = start_host.split('://')
if start_scheme_parts.length() > 1
  start_host = start_scheme_parts[1]
endif
start_host = start_host.split('/')[0]
start_host = start_host.split('?')[0]
start_host = start_host.split('#')[0]
start_userinfo_parts = start_host.split('@')
if start_userinfo_parts.length() > 1
  start_host = start_userinfo_parts[start_userinfo_parts.length() - 1]
endif
if start_host.startswith('[') and start_host.contains(']')
  start_host = start_host.split(']')[0].substring(1)
else
  start_host = start_host.split(':')[0]
endif
start_host = start_host.strip()
start_host_covered = false
foreach entry : site_hosts_list
  host_parts = []
  foreach part : entry.strip().to_lower().split('.')
    if part != ''
      host_parts += [part]
    endif
  endforeach
  candidate = '.'.join(host_parts)
  if candidate != '' and (start_host == candidate or start_host.endswith('.' + candidate))
    start_host_covered = true
  endif
endforeach
if start_host == '' or not start_host_covered
  error('Site config @0@: start_url host "@1@" is not covered by any "host" entry'.format(site_path, start_host))
endif

app_exec = site.get('exec_name', app_id_parts[app_id_parts.length() - 1])
if app_exec == ''
  error('Site config @0@: "exec_name" must not be empty'.format(site_path))
endif
exec_remainder = app_exec
foreach exec_char : id_other_chars
  exec_remainder = exec_remainder.replace(exec_char, '')
endforeach
if exec_remainder != ''
  error('Site config @0@: "exec_name" value "@1@" contains invalid character "@2@" (allowed: A-Z, a-z, 0-9, "_", "-")'.format(site_path, app_exec, exec_remainder.substring(0, 1)))
endif
app_id_path = '/'.join(app_id_parts)
site_icon = site.get('icon')
site_icon_symbolic = site.get('icon_symbolic')
if not fs.is_absolute(site_icon)
  site_icon = meson.project_source_root() / site_icon
endif
if not fs.is_absolute(site_icon_symbolic)
  site_icon_symbolic = meson.project_source_root() / site_icon_symbolic
endif
if not fs.exists(site_icon)
  error('Site config @0@: "icon" file "@1@" does not exist'.format(site_path, site_icon))
endif
if not fs.exists(site_icon_symbolic)
  error('Site config @0@: "icon_symbolic" file "@1@" does not exist'.format(site_path, site_icon_symbolic))
endif
data_dir_root = site.get('data_dir', '')
cache_dir_root = site.get('cache_dir', '')
ephemeral_raw = site.get('ephemeral', 'false').strip().to_lower()
if ephemeral_raw != 'true' and ephemeral_raw != 'false'
  error('Site config @0@: "ephemeral" must be "true" or "false", not "@1@"'.format(site_path, site.get('ephemeral')))
endif
ephemeral = ephemeral_raw == 'true'
persist_cookies_raw = site.get('persist_cookies', 'true').strip().to_lower()
if persist_cookies_raw != 'true' and persist_cookies_raw != 'false'
  error('Site config @0@: "persist_cookies" must be "true" or "false", not "@1@"'.format(site_path, site.get('persist_cookies')))
endif
persist_cookies = persist_cookies_raw == 'true'

config = configuration_data()
config.set_quoted('PACKAGE_VERSION', meson.project_version ())
config.set_quoted('GETTEXT_PACKAGE', app_id)
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
config.set('PERSIST_COOKIES', persist_cookies ? 'TRUE' : 'FALSE')
config_h = configure_file(output: 'config.h', configuration: config)

config_dep = valac.find_library ('config', dirs: srcdir)
config_inc = include_directories('.')

add_project_arguments('-DGETTEXT_PACKAGE="' + app_id + '"', language: 'c')


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
