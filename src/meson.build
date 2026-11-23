webapp_sources = [
  'main.vala',
  'application.vala',
  'utils.vala',
]

webapp_dependencies = [
  config_dep,
  dependency('gtk4', version: '>= 4.12'),
  dependency('webkitgtk-6.0', version: '>= 2.42')
]

webapp_sources += gnome.compile_resources('webapp-resources',
  'webapp.gresource.xml',
  c_name: 'webapp'
)

executable(app_exec, webapp_sources,
  dependencies: webapp_dependencies,
  include_directories: config_inc,
       install: true,
)
