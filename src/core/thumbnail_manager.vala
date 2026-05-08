/* TileFM — ThumbnailManager
 * Integrates with system Tumbler thumbnailer daemon via D-Bus.
 * Falls back to direct Gdk.Pixbuf loading if Tumbler unavailable.
 * Cache stored in ~/.cache/thumbnails/<size>/<hash>.png
 */

namespace TileFm {
    public class ThumbnailManager : Object {
        private static ThumbnailManager? _instance;
        private HashTable<string, Gdk.Pixbuf> cache;
        private const int CACHE_MAX_SIZE = 50;

        private const string TUMBLER_SERVICE = "org.freedesktop.thumbnails.Thumbnailer1";
        private const string TUMBLER_PATH = "/org/freedesktop/thumbnails/Thumbnailer1";

        public static ThumbnailManager get_instance() {
            if (_instance == null) {
                _instance = new ThumbnailManager();
            }
            return _instance;
        }

        private ThumbnailManager() {
            cache = new HashTable<string, Gdk.Pixbuf>(str_hash, str_equal);
        }

        public async Gdk.Pixbuf? get_thumbnail(string path, int size = 256) {
            string cache_key = "%s:%d".printf(path, size);

            Gdk.Pixbuf? cached = cache.lookup(cache_key);
            if (cached != null) {
                return cached;
            }

            string cache_path = get_cached_thumbnail_path(path, size);
            if (cache_path != null && FileUtils.test(cache_path, FileTest.EXISTS)) {
                try {
                    var pixbuf = new Gdk.Pixbuf.from_file(cache_path);
                    if (pixbuf != null) {
                        cache.insert(cache_key, pixbuf);
                        return pixbuf;
                    }
                } catch (Error e) {
                    warning("Failed to load cached thumbnail: %s", e.message);
                }
            }

            return yield generate_thumbnail(path, size, cache_key);
        }

        private async Gdk.Pixbuf? generate_thumbnail(string path, int size, string cache_key) {
            string file_hash = compute_thumbnail_hash(path);
            string thumbnail_dir = get_thumbnail_dir(size);
            string thumbnail_path = Path.build_filename(thumbnail_dir, file_hash + ".png");

            string? thumbnailer_path = find_thumbnailer();
            if (thumbnailer_path != null) {
                try {
                    bool ok = yield call_tumbler(path, thumbnail_path, size);
                    if (ok && FileUtils.test(thumbnail_path, FileTest.EXISTS)) {
                        var pixbuf = new Gdk.Pixbuf.from_file(thumbnail_path);
                        if (pixbuf != null) {
                            cache_pixbuf(cache_key, pixbuf);
                            return pixbuf;
                        }
                    }
                } catch (Error e) {
                    warning("Tumbler thumbnail failed: %s", e.message);
                }
            }

            return yield load_direct_thumbnail(path, cache_key);
        }

        private async Gdk.Pixbuf? load_direct_thumbnail(string path, string cache_key) {
            string mime = get_mime_type(path);
            bool is_image = is_image_mime_type(mime);

            if (!is_image) {
                return null;
            }

            try {
                var pixbuf = new Gdk.Pixbuf.from_file(path);
                if (pixbuf == null) {
                    return null;
                }

                int tw = pixbuf.get_width();
                int th = pixbuf.get_height();
                int target_size = 256;

                if (tw > target_size || th > target_size) {
                    double scale = double.min((double) target_size / tw, (double) target_size / th);
                    int new_w = (int) (tw * scale);
                    int new_h = (int) (th * scale);
                    var scaled = pixbuf.scale_simple(new_w, new_h, Gdk.InterpType.BILINEAR);
                    if (scaled != null) {
                        cache_pixbuf(cache_key, scaled);
                        return scaled;
                    }
                }

                cache_pixbuf(cache_key, pixbuf);
                return pixbuf;
            } catch (Error e) {
                warning("Direct thumbnail load failed: %s", e.message);
                return null;
            }
        }

        private async bool call_tumbler(string path, string thumbnail_path, int size) {
            try {
                var connection = yield Bus.get(BusType.SESSION);

                var proxy = yield connection.call(
                    TUMBLER_SERVICE,
                    TUMBLER_PATH,
                    "org.freedesktop.thumbnails.Thumbnailer1",
                    "Queue",
                    new Variant("(ass)", new string[] { path }),
                    null,
                    DBusCallFlags.NONE,
                    -1
                );

                return true;
            } catch (Error e) {
                warning("Tumbler D-Bus call failed: %s", e.message);
                return false;
            }
        }

        private string? find_thumbnailer() {
            string[] candidates = {
                "/usr/bin/tumbler-thumbnailer",
                "/usr/bin/tumbler",
                "/usr/lib/x86_64-linux-gnu/tumbler-1/tumbler",
                "/usr/lib/tumbler-1/tumbler"
            };

            foreach (var path in candidates) {
                if (FileUtils.test(path, FileTest.EXISTS)) {
                    return path;
                }
            }
            return null;
        }

        private string get_thumbnail_dir(int size) {
            string size_name;
            if (size <= 128) {
                size_name = "small";
            } else if (size <= 256) {
                size_name = "normal";
            } else if (size <= 512) {
                size_name = "large";
            } else {
                size_name = "x-large";
            }

            string base_dir = Path.build_filename(
                Environment.get_user_cache_dir(),
                "thumbnails",
                size_name
            );

            var dir = File.new_for_path(base_dir);
            if (!dir.query_exists()) {
                try {
                    dir.make_directory_with_parents();
                } catch (Error e) {
                    warning("Failed to create thumbnail directory: %s", e.message);
                }
            }

            return base_dir;
        }

        private string get_cached_thumbnail_path(string path, int size) {
            string dir = get_thumbnail_dir(size);
            string hash = compute_thumbnail_hash(path);
            return Path.build_filename(dir, hash + ".png");
        }

        private string compute_thumbnail_hash(string path) {
            string uri = File.new_for_path(path).get_uri();
            return Checksum.compute_for_string(ChecksumType.MD5, uri);
        }

        private bool is_image_mime_type(string mime) {
            string[] image_types = {
                "image/png", "image/jpeg", "image/jpg", "image/gif",
                "image/bmp", "image/x-bmp", "image/svg+xml",
                "image/webp", "image/tiff", "image/x-icon"
            };

            foreach (var t in image_types) {
                if (mime == t) {
                    return true;
                }
            }
            return false;
        }

        private string get_mime_type(string path) {
            try {
                var file = File.new_for_path(path);
                var info = file.query_info(
                    "standard::content-type",
                    FileQueryInfoFlags.NONE
                );
                return info.get_content_type() ?? "application/octet-stream";
            } catch (Error e) {
                return "application/octet-stream";
            }
        }

        private void cache_pixbuf(string key, Gdk.Pixbuf pixbuf) {
            if (cache.size() >= CACHE_MAX_SIZE) {
                var first_key = cache.get_keys().nth_data(0);
                if (first_key != null) {
                    cache.remove(first_key);
                }
            }
            cache.insert(key, pixbuf);
        }

        public void clear_cache() {
            cache.remove_all();
        }
    }
}