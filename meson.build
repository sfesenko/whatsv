project('webapp', ['c', 'vala'],
          version: '0.2.0',
           license: 'MIT',
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
  if key != 'host' and site.has_key(key)
    error('Site config @0@ has duplicate key "@1@"'.format(site_path, key))
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
digits = '0,1,2,3,4,5,6,7,8,9'.split(',')
hex_digits = '0,1,2,3,4,5,6,7,8,9,a,b,c,d,e,f,A,B,C,D,E,F'.split(',')
ipv6_chars = hex_digits + [':', '.']
control_chars = [
  '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', '\x08',
  '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f',
  '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17',
  '\x18', '\x19', '\x1a', '\x1b', '\x1c', '\x1d', '\x1e', '\x1f',
  '\x7f',
]
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

# Reject host entries that would turn the allowlist into a wildcard or that
# can never match at runtime (ports, schemes, paths, single public labels).
foreach entry : site_hosts_list
  host_entry = entry.strip().to_lower()
  if host_entry.startswith('.')
    host_entry = host_entry.substring(1)
  endif
  if host_entry == ''
    error('Site config @0@ has an empty "host" value'.format(site_path))
  endif
  if host_entry.contains('\\')
    error('Site config @0@: host "@1@" must not contain backslashes'.format(site_path, entry.strip()))
  endif
  foreach control : control_chars
    if host_entry.contains(control)
      error('Site config @0@: host "@1@" must not contain control characters'.format(site_path, entry.strip()))
    endif
  endforeach
  if host_entry.contains('/') or host_entry.contains('?') or host_entry.contains('#') or host_entry.contains('@') or host_entry.contains('*') or host_entry.contains(',')
    error('Site config @0@: host "@1@" must be a single hostname, not a URL, wildcard or list'.format(site_path, entry.strip()))
  endif
  if host_entry.contains(' ')
    error('Site config @0@: host "@1@" must not contain spaces'.format(site_path, entry.strip()))
  endif
  if host_entry.startswith('[')
    if not host_entry.endswith(']') or host_entry.split(']').length() != 2
      error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
    endif
    ipv6_inner = host_entry.split(']')[0].substring(1)
    if ipv6_inner == '' or ipv6_inner.contains(':::') or ipv6_inner.split('::').length() > 2 or not ipv6_inner.contains(':')
      error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
    endif
    ipv6_remainder = ipv6_inner
    foreach allowed : ipv6_chars
      ipv6_remainder = ipv6_remainder.replace(allowed, '')
    endforeach
    if ipv6_remainder != ''
      error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
    endif
    ipv6_parts = ipv6_inner.split('::')
    if ipv6_parts.length() > 2
      error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
    endif
    if ipv6_parts.length() == 2 and ipv6_parts[0].contains('.')
      error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
    endif
    ipv6_groups = []
    if ipv6_parts[0] != ''
      ipv6_groups += ipv6_parts[0].split(':')
    endif
    if ipv6_parts.length() == 2 and ipv6_parts[1] != ''
      ipv6_groups += ipv6_parts[1].split(':')
    endif
    ipv6_group_count = ipv6_groups.length()
    foreach group : ipv6_groups
      if group == ''
        error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
      endif
      if group.contains('.')
        if group != ipv6_groups[ipv6_groups.length() - 1]
          error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
        endif
        ipv4_parts = group.split('.')
        if ipv4_parts.length() != 4
          error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
        endif
        foreach ipv4_part : ipv4_parts
          if ipv4_part == ''
            error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
          endif
          ipv4_remainder = ipv4_part
          foreach digit : digits
            ipv4_remainder = ipv4_remainder.replace(digit, '')
          endforeach
          if ipv4_remainder != ''
            error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
          endif
        endforeach
        ipv6_group_count += 1
      else
        if group.substring(4) != ''
          error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
        endif
      endif
    endforeach
    if ipv6_parts.length() == 2
      if ipv6_group_count >= 8
        error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
      endif
    else
      if ipv6_group_count != 8
        error('Site config @0@: host "@1@" has an invalid IPv6 literal'.format(site_path, entry.strip()))
      endif
    endif
  else
    if host_entry.contains(':')
      error('Site config @0@: host "@1@" must not include a port'.format(site_path, entry.strip()))
    endif
    if not host_entry.contains('.') and host_entry != 'localhost'
      error('Site config @0@: host "@1@" must be a fully qualified domain name'.format(site_path, entry.strip()))
    endif
    host_is_numeric = host_entry.contains('.')
    if host_is_numeric
      foreach label : host_entry.split('.')
        label_remainder = label
        foreach digit : digits
          label_remainder = label_remainder.replace(digit, '')
        endforeach
        if label_remainder != ''
          host_is_numeric = false
        endif
      endforeach
      if host_is_numeric and host_entry.split('.').length() != 4
        error('Site config @0@: host "@1@" is not a valid IPv4 address'.format(site_path, entry.strip()))
      endif
    endif
    foreach label : host_entry.split('.')
      if label == ''
        error('Site config @0@: host "@1@" has an empty label'.format(site_path, entry.strip()))
      endif
      if label.startswith('-') or label.endswith('-')
        error('Site config @0@: host "@1@" has an invalid label'.format(site_path, entry.strip()))
      endif
      label_remainder = label
      foreach allowed : id_other_chars
        label_remainder = label_remainder.replace(allowed, '')
      endforeach
      if label_remainder != ''
        error('Site config @0@: host "@1@" contains an invalid character in a label'.format(site_path, entry.strip()))
      endif
    endforeach
  endif
endforeach

app_name = site.get('app_name')
site_start_url = site.get('start_url')
site_hosts = ','.join(site_hosts_list)

# Desktop-entry values cannot contain literal control characters or
# backslashes; reject them at configure time instead of writing a broken file.
if app_name.contains('\\')
  error('Site config @0@: "app_name" must not contain control characters or backslashes'.format(site_path))
endif
foreach control : control_chars
  if app_name.contains(control)
    error('Site config @0@: "app_name" must not contain control characters or backslashes'.format(site_path))
  endif
endforeach

# Values substituted into config.h must not contain C escapes (backslashes)
# or XML-invalid control characters.
foreach key : ['start_url', 'data_dir', 'cache_dir']
  value = site.get(key, '')
  if value.contains('\\')
    error('Site config @0@: "@1@" must not contain backslashes'.format(site_path, key))
  endif
  foreach control : control_chars
    if value.contains(control)
      error('Site config @0@: "@1@" must not contain control characters'.format(site_path, key))
    endif
  endforeach
endforeach

# AppStream is XML: escape values before they are substituted into the
# template, otherwise names/URLs containing '&' or '<' break the build.
app_name_xml = app_name.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&apos;')
site_start_url_xml = site_start_url.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&apos;')

# The start URL must be a web URL, otherwise the runtime navigation policy
# refuses it and the app opens a blank window.
start_url_lower = site_start_url.strip().to_lower()
if not (start_url_lower.startswith('http://') or start_url_lower.startswith('https://'))
  error('Site config @0@: "start_url" must use http:// or https://'.format(site_path))
endif

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
start_authority = start_host
if start_authority.startswith('[')
  if not start_authority.contains(']') or start_authority.split(']').length() > 2
    error('Site config @0@: "start_url" has an invalid host or port'.format(site_path))
  endif
  start_after_host = start_authority.split(']')[1]
  if start_after_host != ''
    if not start_after_host.startswith(':') or start_after_host.split(':').length() != 2
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    start_port = start_after_host.substring(1)
    if start_port == ''
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    start_port_remainder = start_port
    foreach digit : digits
      start_port_remainder = start_port_remainder.replace(digit, '')
    endforeach
    if start_port_remainder != ''
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    if start_port.to_int() > 65535
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
  endif
  start_host = start_authority.split(']')[0].substring(1)
else
  if start_authority.contains(':')
    if start_authority.split(':').length() != 2
      error('Site config @0@: "start_url" has an invalid host or port'.format(site_path))
    endif
    start_port = start_authority.split(':')[1]
    if start_port == ''
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    start_port_remainder = start_port
    foreach digit : digits
      start_port_remainder = start_port_remainder.replace(digit, '')
    endforeach
    if start_port_remainder != ''
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    if start_port.to_int() > 65535
      error('Site config @0@: "start_url" has an invalid port'.format(site_path))
    endif
    start_host = start_authority.split(':')[0]
  else
    start_host = start_authority
  endif
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
  if candidate.startswith('[') and candidate.endswith(']')
    candidate = candidate.split(']')[0].substring(1)
  endif
  candidate_is_numeric = candidate.contains('.')
  candidate_labels = candidate.split('.')
  if candidate_is_numeric
    foreach label : candidate_labels
      label_remainder = label
      foreach digit : digits
        label_remainder = label_remainder.replace(digit, '')
      endforeach
      if label_remainder != ''
        candidate_is_numeric = false
      endif
    endforeach
  endif
  candidate_is_single_label = not candidate.contains('.')
  if candidate != '' and (start_host == candidate or (not candidate_is_single_label and not candidate_is_numeric and start_host.endswith('.' + candidate)))
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
if app_exec.startswith('-')
  error('Site config @0@: "exec_name" must not start with "-"'.format(site_path))
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
if data_dir_root != '' and not fs.is_absolute(data_dir_root)
  error('Site config @0@: "data_dir" must be an absolute path'.format(site_path))
endif
if cache_dir_root != '' and not fs.is_absolute(cache_dir_root)
  error('Site config @0@: "cache_dir" must be an absolute path'.format(site_path))
endif
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

install_data('COPYING', install_dir: get_option('datadir') / 'licenses' / app_id)

# Version bump helpers: meson compile -C build bump-patch / bump-minor / bump-major
run_target('bump-patch', command: [find_program('python3'), files('scripts/bump.py'), '--patch'])
run_target('bump-minor', command: [find_program('python3'), files('scripts/bump.py'), '--minor'])
run_target('bump-major', command: [find_program('python3'), files('scripts/bump.py'), '--major'])

gnome.post_install(
     glib_compile_schemas: true,
    gtk_update_icon_cache: true,
  update_desktop_database: true,
)
