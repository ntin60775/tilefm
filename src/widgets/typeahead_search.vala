/*
 * TileFM - Typeahead Search Widget
 *
 * Gtk.Entry inside Gtk.Revealer, shown/hidden over a Tile.
 * Filters files in real-time as the user types (debounced).
 */
public class TypeaheadSearch : Gtk.Revealer {
    /**
     * Emitted when the search text changes (after debounce).
     * @param query The current search query (may be empty).
     */
    public signal void search_changed (string query);

    /**
     * Emitted when the search widget is dismissed (Escape pressed
     * or programmatic close). The Tile should restore the full
     * file list when this fires.
     */
    public signal void search_closed ();

    /**
     * Emitted when the user presses the Down arrow.
     * The Tile should select the next visible result.
     */
    public signal void navigate_next ();

    /**
     * Emitted when the user presses the Up arrow.
     * The Tile should select the previous visible result.
     */
    public signal void navigate_prev ();

    /**
     * Emitted when the user presses Enter.
     * The Tile should activate (open) the currently selected file.
     */
    public signal void activate_current ();

    /**
     * Whether the search widget is currently open and active.
     */
    public bool is_searching { get; private set; }

    /* ── internal widgets ────────────────────────────────────────────── */

    private Gtk.Entry  entry;
    private Gtk.Box    hbox;
    private Gtk.Label  status_label;

    /* Debounce timer ID.  0 == no timer running. */
    private uint debounce_source = 0;

    /* Const debounce interval (ms). */
    private const uint DEBOUNCE_MS = 100;

    /* ── construction ────────────────────────────────────────────────── */

    public TypeaheadSearch () {
        /* Revealer settings */
        transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN;
        transition_duration = 150;
        reveal_child = false;

        /* Horizontal container: entry + status label */
        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
        hbox.margin = 6;

        /* Search entry */
        entry = new Gtk.Entry ();
        entry.placeholder_text = "Filter files…";
        entry.set_icon_from_icon_name (
            Gtk.EntryIconPosition.PRIMARY,
            "edit-find-symbolic"
        );
        entry.set_icon_from_icon_name (
            Gtk.EntryIconPosition.SECONDARY,
            "edit-clear-symbolic"
        );
        entry.hexpand = true;

        /* Status label — shows "3/12" */
        status_label = new Gtk.Label ("");
        status_label.no_show_all = true;
        status_label.hide ();
        status_label.get_style_context ().add_class ("dim-label");

        hbox.pack_start (entry, true,  true,  0);
        hbox.pack_end   (status_label, false, false, 0);

        add (hbox);

        /* ── key handling ───────────────────────────────────────────── */
        entry.key_press_event.connect (on_key_press);

        /* ── text change with debounce ──────────────────────────────── */
        entry.changed.connect (on_entry_changed);

        /* ── clear icon clicked ─────────────────────────────────────── */
        entry.icon_release.connect ((icon_pos, ev) => {
            if (icon_pos == Gtk.EntryIconPosition.SECONDARY) {
                entry.text = "";
                /* Changing text triggers on_entry_changed → full restore */
            }
        });

        /* ── activate (Enter on entry) ──────────────────────────────── */
        entry.activate.connect (() => {
            activate_current ();
        });
    }

    /* ── public API ──────────────────────────────────────────────────── */

    /**
     * Opens (reveals) the search widget, grabs focus on the entry and
     * selects any existing text so the user can type immediately.
     */
    public void show_search () {
        reveal_child = true;
        is_searching = true;
        entry.grab_focus ();
        entry.select_region (0, -1);
    }

    /**
     * Closes (hides) the search widget and clears the query.
     * Emits @search_closed so the Tile can restore the full list.
     */
    public void hide_search () {
        reveal_child = false;
        is_searching = false;

        /* Clear without triggering the changed signal – we are closing */
        SignalHandler.block_by_func (entry, (void*) on_entry_changed, this);
        entry.text = "";
        SignalHandler.unblock_by_func (entry, (void*) on_entry_changed, this);

        status_label.hide ();
        search_closed ();
    }

    /**
     * Returns the current search query.
     */
    public string get_query () {
        return entry.text;
    }

    /**
     * Updates the status label, e.g. "3/12".
     * If @total is zero the label is hidden.
     */
    public void set_info (uint current, uint total) {
        if (total == 0) {
            status_label.hide ();
        } else {
            status_label.label = "%u/%u".printf (current, total);
            status_label.show ();
        }
    }

    /* ── private helpers ─────────────────────────────────────────────── */

    private bool on_key_press (Gdk.EventKey ev) {
        switch (ev.keyval) {
            case Gdk.Key.Escape:
                hide_search ();
                return true;

            case Gdk.Key.Down:
            case Gdk.Key.KP_Down:
                navigate_next ();
                return true;

            case Gdk.Key.Up:
            case Gdk.Key.KP_Up:
                navigate_prev ();
                return true;

            default:
                return false;
        }
    }

    /**
     * Called every time the Gtk.Entry text changes.
     * We restart a 100 ms timeout so rapid typing does not flood
     * the Tile with filter requests.
     */
    private void on_entry_changed () {
        /* Remove previous pending timeout */
        if (debounce_source != 0) {
            Source.remove (debounce_source);
            debounce_source = 0;
        }

        debounce_source = Timeout.add (DEBOUNCE_MS, () => {
            debounce_source = 0;
            search_changed (entry.text);
            return Source.REMOVE;
        });
    }
}
