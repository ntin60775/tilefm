sources = files(
    'main.vala',
    'application.vala',
    'window.vala',
    'core/file_manager.vala',
    'core/async_worker.vala',
    'core/layout_manager.vala',
    'tile/tile.vala',
    'tile/tile_container.vala',
    'view/file_view.vala',
    'view/icon_view.vala',
    'view/list_view.vala',
    'widgets/breadcrumb_pathbar.vala',
)

tilefm_deps = [
    glib_dep,
    gobject_dep,
    gtk_dep,
    gio_dep,
    gee_dep,
    json_dep,
]

executable('tilefm',
    sources,
    dependencies: tilefm_deps,
    install: true,
)
