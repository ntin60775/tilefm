/*
 * TileFM - File Searcher
 *
 * Static helpers for filtering FileInfo[] arrays against a
 * user-supplied query.  Supports plain substring search (case-
 * insensitive) as well as glob-style patterns like "*.txt" or
 * "file*".
 */
public class FileSearcher : Object {

    /**
     * Filters an array of FileInfo objects, returning only those
     * whose display name matches the given query.
     *
     * - An empty or whitespace-only @query returns a shallow copy
     *   of the original array (all files visible).
     * - Otherwise only entries for which matches(name, query) is
     *   true are kept.
     *
     * @param infos  Array of FileInfo to filter.
     * @param query  Search string; may contain glob wildcards.
     * @return       Newly-allocated array with matching entries.
     */
    public static FileInfo[] filter (FileInfo[] infos, string query) {
        /* Empty query → everything visible */
        if (query == null || query.strip ().length == 0) {
            return infos;
        }

        string q = query.strip ();

        Gee.ArrayList<FileInfo> result =
            new Gee.ArrayList<FileInfo> ();

        foreach (FileInfo info in infos) {
            if (matches (info.get_display_name (), q)) {
                result.add (info);
            }
        }

        return list_to_array (result);
    }

    /**
     * Checks whether @filename matches @query.
     *
     * Rules (applied in order):
     *   1. If @query contains '*' or '?' it is treated as a glob
     *      pattern and matched via Glib.PatternSpec.
     *   2. Otherwise a case-insensitive substring search is used.
     *
     * Both leading and trailing whitespace in @query is ignored.
     *
     * @param filename  Name of the file (without path).
     * @param query     Search string entered by the user.
     * @return          true when the filename matches the query.
     */
    public static bool matches (string filename, string query) {
        if (query == null || query.strip ().length == 0) {
            return true;
        }

        string q = query.strip ();

        /* 1. Glob mode */
        if (q.index_of_char ('*') >= 0 || q.index_of_char ('?') >= 0) {
            /* PatternSpec works case-insensitively when we down-case
             * both sides. */
            var spec = new PatternSpec (q.down ());
            return spec.match_string (filename.down ());
        }

        /* 2. Plain substring search (case-insensitive) */
        return filename.down ().contains (q.down ());
    }

    /* ── helpers ─────────────────────────────────────────────────────── */

    /**
     * Converts a Gee.ArrayList<FileInfo> into a native Vala array.
     */
    private static FileInfo[] list_to_array (Gee.ArrayList<FileInfo> list) {
        FileInfo[] arr = new FileInfo[list.size];
        for (int i = 0; i < list.size; i++) {
            arr[i] = list.get (i);
        }
        return arr;
    }
}
