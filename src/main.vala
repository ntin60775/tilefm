/* TileFM — Tile-based File Manager for XFCE
 * Main entry point
 * GPL-3.0+ License
 */

public static int main(string[] args) {
    var app = new TileFm.Application();
    return app.run(args);
}
