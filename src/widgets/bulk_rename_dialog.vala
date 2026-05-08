/*
 * bulk_rename_dialog.vala - TileFM Bulk Rename Dialog
 *
 * Mass-rename dialog with multiple modes:
 *   - Find & Replace
 *   - Numbering (prefix_001, prefix_002, ...)
 *   - Insert text at position
 *   - Remove N characters at position
 *   - Change extension
 *
 * Shows live preview of old names vs new names before applying.
 */

using Gtk;
using GLib;

public enum RenameMode {
    FIND_REPLACE,
    NUMBERING,
    INSERT,
    REMOVE,
    EXTENSION
}

public class BulkRenameDialog : Gtk.Dialog {

    /**
     * Emitted when the user clicks the Rename button.
     * @param old_paths  Original file paths (full paths).
     * @param new_names  New filenames (not full paths — just the new names).
     */
    public signal void apply_rename (string[] old_paths, string[] new_names);

    /* ── data ─────────────────────────────────────────────────── */
    private string[] file_paths;
    private string[] old_names;
    private string[] new_names;

    /* ── UI widgets ───────────────────────────────────────────── */
    private Gtk.ListStore     list_store;
    private Gtk.TreeView      tree_view;
    private Gtk.ComboBoxText  mode_combo;
    private Gtk.Stack         mode_stack;

    /* Find & Replace widgets */
    private Gtk.Entry         fr_find_entry;
    private Gtk.Entry         fr_replace_entry;
    private Gtk.CheckButton   fr_case_sensitive;
    private Gtk.CheckButton   fr_regex;

    /* Numbering widgets */
    private Gtk.Entry         num_prefix_entry;
    private Gtk.Entry         num_suffix_entry;
    private Gtk.SpinButton    num_start_spin;
    private Gtk.SpinButton    num_width_spin;

    /* Insert widgets */
    private Gtk.Entry         insert_text_entry;
    private Gtk.SpinButton    insert_pos_spin;

    /* Remove widgets */
    private Gtk.SpinButton    remove_start_spin;
    private Gtk.SpinButton    remove_count_spin;

    /* Extension widgets */
    private Gtk.Entry         ext_new_entry;

    private Gtk.Label         preview_label;

    /* ── construction ─────────────────────────────────────────── */

    public BulkRenameDialog (Gtk.Window parent, string[] paths) {
        Object (
            title: "Bulk Rename",
            transient_for: parent,
            modal: true,
            destroy_with_parent: true,
            use_header_bar: 1,  /* Use header bar */
            default_width: 620,
            default_height: 520
        );

        this.file_paths = paths;
        this.old_names = new string[paths.length];
        for (int i = 0; i < paths.length; i++) {
            old_names[i] = Path.get_basename (paths[i]);
        }
        this.new_names = new string[paths.length];

        setup_ui ();
        setup_headerbar ();
        connect_signals ();
        generate_preview ();
    }

    /* ── public API ───────────────────────────────────────────── */

    /**
     * Returns the computed new names (one per input file).
     */
    public string[] get_new_names () {
        return new_names;
    }

    /* ── UI setup ─────────────────────────────────────────────── */

    private void setup_headerbar () {
        /* The header bar is created automatically by use_header_bar=1,
           but we need to add our action buttons to it. */

        /* Cancel button */
        add_button ("_Cancel", Gtk.ResponseType.CANCEL);

        /* Preview button (non-default) */
        var preview_btn = new Gtk.Button.with_label ("Preview");
        preview_btn.tooltip_text = "Refresh preview (Ctrl+P)";
        preview_btn.clicked.connect (() => generate_preview ());
        add_action_widget (preview_btn, Gtk.ResponseType.APPLY);

        /* Rename button (suggested action) */
        var rename_btn = new Gtk.Button.with_label ("Rename");
        rename_btn.get_style_context ().add_class ("suggested-action");
        rename_btn.tooltip_text = "Apply rename operation";
        rename_btn.clicked.connect (() => {
            generate_preview ();
            do_apply ();
        });
        add_action_widget (rename_btn, Gtk.ResponseType.ACCEPT);

        set_default_response (Gtk.ResponseType.ACCEPT);
    }

    private void setup_ui () {
        var content = get_content_area ();
        content.spacing = 8;
        content.margin = 8;

        /* ── Mode selector ── */
        var mode_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        mode_box.margin_bottom = 4;

        var mode_label = new Gtk.Label ("Mode:");
        mode_label.halign = Gtk.Align.START;
        mode_box.pack_start (mode_label, false, false, 0);

        mode_combo = new Gtk.ComboBoxText ();
        mode_combo.append ("find_replace", "Find & Replace");
        mode_combo.append ("numbering", "Numbering");
        mode_combo.append ("insert", "Insert");
        mode_combo.append ("remove", "Remove");
        mode_combo.append ("extension", "Extension");
        mode_combo.set_active (0);
        mode_box.pack_start (mode_combo, false, false, 0);

        content.pack_start (mode_box, false, false, 0);

        /* ── Mode-specific options (stack) ── */
        mode_stack = new Gtk.Stack ();
        mode_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
        mode_stack.set_transition_duration (150);
        mode_stack.margin_bottom = 8;

        setup_find_replace_page ();
        setup_numbering_page ();
        setup_insert_page ();
        setup_remove_page ();
        setup_extension_page ();

        content.pack_start (mode_stack, false, false, 0);

        /* ── Preview list ── */
        var list_frame = new Gtk.Frame ("Preview: Old Name -> New Name");
        list_frame.expand = true;

        list_store = new Gtk.ListStore (3,
            typeof (string),   /* index */
            typeof (string),   /* old name */
            typeof (string)    /* new name */
        );

        tree_view = new Gtk.TreeView.with_model (list_store);
        tree_view.headers_visible = true;

        /* Column: # */
        var col_idx = new Gtk.TreeViewColumn ();
        col_idx.title = "#";
        var cell_idx = new Gtk.CellRendererText ();
        col_idx.pack_start (cell_idx, true);
        col_idx.add_attribute (cell_idx, "text", 0);
        col_idx.set_min_width (36);
        tree_view.append_column (col_idx);

        /* Column: Old Name */
        var col_old = new Gtk.TreeViewColumn ();
        col_old.title = "Old Name";
        col_old.set_min_width (220);
        var cell_old = new Gtk.CellRendererText ();
        cell_old.ellipsize = Pango.EllipsizeMode.END;
        col_old.pack_start (cell_old, true);
        col_old.add_attribute (cell_old, "text", 1);
        tree_view.append_column (col_old);

        /* Column: New Name (bold) */
        var col_new = new Gtk.TreeViewColumn ();
        col_new.title = "New Name";
        col_new.set_min_width (220);
        var cell_new = new Gtk.CellRendererText ();
        cell_new.weight = 700;
        cell_new.ellipsize = Pango.EllipsizeMode.END;
        cell_new.foreground = "#2e7d32";
        col_new.pack_start (cell_new, true);
        col_new.add_attribute (cell_new, "text", 2);
        tree_view.append_column (col_new);

        var scrolled = new Gtk.ScrolledWindow (null, null);
        scrolled.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scrolled.add (tree_view);
        scrolled.expand = true;

        list_frame.add (scrolled);
        content.pack_start (list_frame, true, true, 0);

        /* ── Preview status label ── */
        preview_label = new Gtk.Label ("");
        preview_label.halign = Gtk.Align.START;
        preview_label.use_markup = true;
        content.pack_start (preview_label, false, false, 0);

        content.show_all ();
    }

    private void setup_find_replace_page () {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 6;
        grid.column_spacing = 8;
        grid.margin = 8;

        var find_lbl = new Gtk.Label ("Find:");
        find_lbl.halign = Gtk.Align.END;
        grid.attach (find_lbl, 0, 0, 1, 1);
        fr_find_entry = new Gtk.Entry ();
        fr_find_entry.hexpand = true;
        fr_find_entry.set_text ("");
        grid.attach (fr_find_entry, 1, 0, 1, 1);

        var repl_lbl = new Gtk.Label ("Replace:");
        repl_lbl.halign = Gtk.Align.END;
        grid.attach (repl_lbl, 0, 1, 1, 1);
        fr_replace_entry = new Gtk.Entry ();
        fr_replace_entry.set_text ("");
        grid.attach (fr_replace_entry, 1, 1, 1, 1);

        fr_case_sensitive = new Gtk.CheckButton.with_label ("Case sensitive");
        fr_case_sensitive.active = false;
        grid.attach (fr_case_sensitive, 1, 2, 1, 1);

        fr_regex = new Gtk.CheckButton.with_label ("Regular expression");
        fr_regex.active = false;
        grid.attach (fr_regex, 1, 3, 1, 1);

        mode_stack.add_named (grid, "find_replace");
    }

    private void setup_numbering_page () {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 6;
        grid.column_spacing = 8;
        grid.margin = 8;

        var pre_lbl = new Gtk.Label ("Prefix:");
        pre_lbl.halign = Gtk.Align.END;
        grid.attach (pre_lbl, 0, 0, 1, 1);
        num_prefix_entry = new Gtk.Entry ();
        num_prefix_entry.set_text ("file_");
        grid.attach (num_prefix_entry, 1, 0, 1, 1);

        var suf_lbl = new Gtk.Label ("Suffix:");
        suf_lbl.halign = Gtk.Align.END;
        grid.attach (suf_lbl, 0, 1, 1, 1);
        num_suffix_entry = new Gtk.Entry ();
        num_suffix_entry.set_text ("");
        grid.attach (num_suffix_entry, 1, 1, 1, 1);

        var start_lbl = new Gtk.Label ("Start at:");
        start_lbl.halign = Gtk.Align.END;
        grid.attach (start_lbl, 0, 2, 1, 1);
        num_start_spin = new Gtk.SpinButton.with_range (0, 99999, 1);
        num_start_spin.value = 1;
        grid.attach (num_start_spin, 1, 2, 1, 1);

        var width_lbl = new Gtk.Label ("Number width:");
        width_lbl.halign = Gtk.Align.END;
        grid.attach (width_lbl, 0, 3, 1, 1);
        num_width_spin = new Gtk.SpinButton.with_range (1, 10, 1);
        num_width_spin.value = 3;
        grid.attach (num_width_spin, 1, 3, 1, 1);

        mode_stack.add_named (grid, "numbering");
    }

    private void setup_insert_page () {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 6;
        grid.column_spacing = 8;
        grid.margin = 8;

        var txt_lbl = new Gtk.Label ("Text to insert:");
        txt_lbl.halign = Gtk.Align.END;
        grid.attach (txt_lbl, 0, 0, 1, 1);
        insert_text_entry = new Gtk.Entry ();
        insert_text_entry.set_text ("_new");
        grid.attach (insert_text_entry, 1, 0, 1, 1);

        var pos_lbl = new Gtk.Label ("Position:");
        pos_lbl.halign = Gtk.Align.END;
        grid.attach (pos_lbl, 0, 1, 1, 1);
        insert_pos_spin = new Gtk.SpinButton.with_range (0, 999, 1);
        insert_pos_spin.value = 0;
        grid.attach (insert_pos_spin, 1, 1, 1, 1);

        var hint = new Gtk.Label ("<span size='small' color='#888888'>Position 0 = beginning, negative values = from end</span>");
        hint.use_markup = true;
        hint.halign = Gtk.Align.START;
        grid.attach (hint, 1, 2, 1, 1);

        mode_stack.add_named (grid, "insert");
    }

    private void setup_remove_page () {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 6;
        grid.column_spacing = 8;
        grid.margin = 8;

        var start_lbl = new Gtk.Label ("Start position:");
        start_lbl.halign = Gtk.Align.END;
        grid.attach (start_lbl, 0, 0, 1, 1);
        remove_start_spin = new Gtk.SpinButton.with_range (0, 999, 1);
        remove_start_spin.value = 0;
        grid.attach (remove_start_spin, 1, 0, 1, 1);

        var cnt_lbl = new Gtk.Label ("Count:");
        cnt_lbl.halign = Gtk.Align.END;
        grid.attach (cnt_lbl, 0, 1, 1, 1);
        remove_count_spin = new Gtk.SpinButton.with_range (1, 999, 1);
        remove_count_spin.value = 3;
        grid.attach (remove_count_spin, 1, 1, 1, 1);

        var hint = new Gtk.Label ("<span size='small' color='#888888'>Remove N characters starting at the given position</span>");
        hint.use_markup = true;
        hint.halign = Gtk.Align.START;
        grid.attach (hint, 1, 2, 1, 1);

        mode_stack.add_named (grid, "remove");
    }

    private void setup_extension_page () {
        var grid = new Gtk.Grid ();
        grid.row_spacing = 6;
        grid.column_spacing = 8;
        grid.margin = 8;

        var ext_lbl = new Gtk.Label ("New extension:");
        ext_lbl.halign = Gtk.Align.END;
        grid.attach (ext_lbl, 0, 0, 1, 1);
        ext_new_entry = new Gtk.Entry ();
        ext_new_entry.set_text ("txt");
        ext_new_entry.set_placeholder_text ("e.g. txt, pdf, jpg");
        grid.attach (ext_new_entry, 1, 0, 1, 1);

        var hint = new Gtk.Label ("<span size='small' color='#888888'>Replace the extension of all selected files</span>");
        hint.use_markup = true;
        hint.halign = Gtk.Align.START;
        grid.attach (hint, 1, 1, 1, 1);

        mode_stack.add_named (grid, "extension");
    }

    private void connect_signals () {
        /* Mode combo drives the stack */
        mode_combo.changed.connect (() => {
            string active_id = mode_combo.get_active_id () ?? "find_replace";
            mode_stack.set_visible_child_name (active_id);
            generate_preview ();
        });

        /* Regenerate preview on any option change */
        fr_find_entry.changed.connect (generate_preview);
        fr_replace_entry.changed.connect (generate_preview);
        fr_case_sensitive.toggled.connect (generate_preview);
        fr_regex.toggled.connect (generate_preview);

        num_prefix_entry.changed.connect (generate_preview);
        num_suffix_entry.changed.connect (generate_preview);
        num_start_spin.value_changed.connect (generate_preview);
        num_width_spin.value_changed.connect (generate_preview);

        insert_text_entry.changed.connect (generate_preview);
        insert_pos_spin.value_changed.connect (generate_preview);

        remove_start_spin.value_changed.connect (generate_preview);
        remove_count_spin.value_changed.connect (generate_preview);

        ext_new_entry.changed.connect (generate_preview);

        /* Dialog response */
        response.connect ((response_id) => {
            switch (response_id) {
                case Gtk.ResponseType.APPLY:
                    generate_preview ();
                    break;
                case Gtk.ResponseType.ACCEPT:
                    generate_preview ();
                    do_apply ();
                    break;
                case Gtk.ResponseType.CANCEL:
                case Gtk.ResponseType.DELETE_EVENT:
                    destroy ();
                    break;
            }
        });

        /* Key shortcuts: Ctrl+P = preview refresh */
        key_press_event.connect ((event) => {
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0
                && event.keyval == Gdk.Key.p) {
                generate_preview ();
                return true;
            }
            if (event.keyval == Gdk.Key.Return || event.keyval == Gdk.Key.KP_Enter) {
                generate_preview ();
                do_apply ();
                return true;
            }
            return false;
        });
    }

    /* ── Preview engine ───────────────────────────────────────── */

    private void generate_preview () {
        RenameMode mode = get_current_mode ();
        int changed_count = 0;

        for (int i = 0; i < old_names.length; i++) {
            string old_name = old_names[i];
            string new_name = old_name;

            switch (mode) {
                case RenameMode.FIND_REPLACE:
                    new_name = apply_find_replace (old_name);
                    break;
                case RenameMode.NUMBERING:
                    new_name = apply_numbering (i);
                    break;
                case RenameMode.INSERT:
                    new_name = apply_insert (old_name);
                    break;
                case RenameMode.REMOVE:
                    new_name = apply_remove (old_name);
                    break;
                case RenameMode.EXTENSION:
                    new_name = apply_extension (old_name);
                    break;
            }

            new_names[i] = new_name;
            if (new_name != old_name) {
                changed_count++;
            }

            /* Update list store */
            Gtk.TreeIter iter;
            list_store.insert_with_values (out iter, i,
                0, (i + 1).to_string (),
                1, old_name,
                2, new_name
            );
        }

        /* Remove excess rows if file count shrank (shouldn't happen) */
        while (list_store.iter_n_children (null) > old_names.length) {
            Gtk.TreeIter last;
            if (list_store.iter_nth_child (out last, null, old_names.length)) {
                list_store.remove (ref last);
            }
        }

        /* Update status label */
        if (changed_count == 0) {
            preview_label.set_markup ("<span color='#cc4444'>No files will be changed</span>");
        } else {
            preview_label.set_markup (
                "<span color='#2e7d32'><b>%d</b> of <b>%d</b> files will be renamed</span>"
                .printf (changed_count, old_names.length)
            );
        }
    }

    /* ── Rename mode implementations ──────────────────────────── */

    private RenameMode get_current_mode () {
        string id = mode_combo.get_active_id () ?? "find_replace";
        switch (id) {
            case "find_replace":  return RenameMode.FIND_REPLACE;
            case "numbering":     return RenameMode.NUMBERING;
            case "insert":        return RenameMode.INSERT;
            case "remove":        return RenameMode.REMOVE;
            case "extension":     return RenameMode.EXTENSION;
            default:              return RenameMode.FIND_REPLACE;
        }
    }

    private string apply_find_replace (string input) {
        string find = fr_find_entry.get_text ();
        if (find == "") return input;

        string replace = fr_replace_entry.get_text ();
        bool case_sens = fr_case_sensitive.active;
        bool use_regex = fr_regex.active;

        if (use_regex) {
            try {
                var flags = case_sens ? RegexCompileFlags.DEFAULT
                                      : RegexCompileFlags.CASELESS;
                var regex = new Regex (find, flags);
                return regex.replace (input, input.length, 0, replace);
            } catch (RegexError e) {
                warning ("Invalid regex: %s", e.message);
                return input;
            }
        } else {
            if (case_sens) {
                return input.replace (find, replace);
            } else {
                /* Case-insensitive string replacement */
                return replace_ic (input, find, replace);
            }
        }
    }

    private string replace_ic (string input, string find, string replace) {
        if (find == "") return input;
        string input_lower = input.ascii_down ();
        string find_lower = find.ascii_down ();

        var sb = new StringBuilder ();
        int last = 0;
        int idx;

        while ((idx = input_lower.index_of (find_lower, last)) >= 0) {
            sb.append (input[last:idx]);
            sb.append (replace);
            last = idx + find.length;
        }
        sb.append (input[last:input.length]);
        return sb.str;
    }

    private string apply_numbering (int index) {
        string prefix = num_prefix_entry.get_text ();
        string suffix = num_suffix_entry.get_text ();
        int start = (int) num_start_spin.get_value ();
        int width = (int) num_width_spin.get_value ();

        int number = start + index;
        string fmt = "%s%0" + width.to_string () + "d%s";
        return fmt.printf (prefix, number, suffix);
    }

    private string apply_insert (string input) {
        string text = insert_text_entry.get_text ();
        int pos = (int) insert_pos_spin.get_value ();

        if (text == "") return input;

        int eff_pos;
        if (pos < 0) {
            eff_pos = input.length + pos;
        } else {
            eff_pos = pos;
        }

        eff_pos = eff_pos.clamp (0, input.length);
        return input.substring (0, eff_pos) + text + input.substring (eff_pos);
    }

    private string apply_remove (string input) {
        int start = (int) remove_start_spin.get_value ();
        int count = (int) remove_count_spin.get_value ();

        if (start >= input.length || count <= 0) return input;

        string before = input.substring (0, start);
        string after = input.substring ((start + count).clamp (0, input.length));
        return before + after;
    }

    private string apply_extension (string input) {
        string new_ext = ext_new_entry.get_text ().strip ();
        if (new_ext == "") return input;

        /* Strip leading dot if user added one */
        if (new_ext.has_prefix (".")) {
            new_ext = new_ext.substring (1);
        }

        int last_dot = input.last_index_of (".");
        if (last_dot < 0) {
            /* No existing extension */
            return input + "." + new_ext;
        } else {
            return input.substring (0, last_dot) + "." + new_ext;
        }
    }

    /* ── Apply / execute ──────────────────────────────────────── */

    private void do_apply () {
        /* Validate: no duplicate names */
        var seen = new Gee.HashSet<string> ();
        for (int i = 0; i < new_names.length; i++) {
            if (new_names[i] == old_names[i]) continue; /* unchanged */
            if (seen.contains (new_names[i])) {
                show_error ("Duplicate name detected: '%s'".printf (new_names[i]));
                return;
            }
            seen.add (new_names[i]);
        }

        /* Validate: no name collisions with existing files */
        string parent_dir = ".";
        if (file_paths.length > 0) {
            var f = File.new_for_path (file_paths[0]);
            var p = f.get_parent ();
            if (p != null) parent_dir = p.get_path ();
        }

        for (int i = 0; i < new_names.length; i++) {
            if (new_names[i] == old_names[i]) continue;
            string check_path = Path.build_filename (parent_dir, new_names[i]);
            if (FileUtils.test (check_path, FileTest.EXISTS)) {
                show_error ("File already exists: '%s'".printf (new_names[i]));
                return;
            }
        }

        /* All clear — emit signal and close */
        apply_rename (file_paths, new_names);
        destroy ();
    }

    private void show_error (string message) {
        var dialog = new Gtk.MessageDialog (
            this,
            Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
            Gtk.MessageType.ERROR,
            Gtk.ButtonsType.CLOSE,
            "%s", message
        );
        dialog.run ();
        dialog.destroy ();
    }
}
