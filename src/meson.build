whatsv_sources = [
  'main.vala',
  'application.vala',
]

whatsv_dependencies = [
  config_dep,
  dependency('gtk4', version: '>= 4.12'),
  dependency('webkitgtk-6.0', version: '>= 2.42')
]

whatsv_sources += gnome.compile_resources('whatsv-resources',
  'whatsv.gresource.xml',
  c_name: 'whatsv'
)

executable('whatsv', whatsv_sources,
  dependencies: whatsv_dependencies,
  include_directories: config_inc,
       install: true,
       gui_app: true,
)
