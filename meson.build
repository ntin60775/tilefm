project('tilefm', 'vala', 'c',
    version: '0.1.0',
    meson_version: '>= 0.50.0',
    default_options: [
        'warning_level=2',
        'c_std=gnu11',
    ],
)

# Dependencies
glib_dep = dependency('glib-2.0', version: '>= 2.50')
gobject_dep = dependency('gobject-2.0', version: '>= 2.50')
gtk_dep = dependency('gtk+-3.0', version: '>= 3.22')
gio_dep = dependency('gio-2.0', version: '>= 2.50')
gee_dep = dependency('gee-0.8', version: '>= 0.20')
json_dep = dependency('json-glib-1.0', version: '>= 1.0')

# Configuration
data_dir = get_option('datadir')
pkg_data_dir = join_paths(data_dir, 'tilefm')

conf_data = configuration_data()
conf_data.set('VERSION', meson.project_version())
conf_data.set('PKGDATADIR', pkg_data_dir)

# Subdirectories
subdir('src')
subdir('data')
