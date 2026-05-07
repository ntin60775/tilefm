desktop_file = configure_file(
    input: 'com.github.tilefm.desktop.in',
    output: 'com.github.tilefm.desktop',
    configuration: conf_data,
    install: true,
    install_dir: join_paths(data_dir, 'applications')
)

# Validate desktop file
desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
    test('validate-desktop',
        desktop_file_validate,
        args: [desktop_file]
    )
endif
