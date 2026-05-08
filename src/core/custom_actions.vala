/*
 * custom_actions.vala
 * TileFM — Thunar Custom Actions (uca.xml) parser and executor
 */

namespace TileFm {

public class CustomAction : Object {
    public string id { get; set; default = ""; }
    public string name { get; set; default = ""; }
    public string icon { get; set; default = ""; }
    public string command { get; set; default = ""; }
    public string description { get; set; default = ""; }
    public bool on_files { get; set; default = false; }
    public bool on_directories { get; set; default = false; }
    public string[] patterns { get; set; default = new string[] {"*"}; }

    public string build_command(string path) {
        var file = File.new_for_path(path);
        string basename = file.get_basename() ?? path;
        string parent = file.get_parent()?.get_path() ?? ".";

        string result = command;
        result = result.replace("%f", Shell.quote(path));
        result = result.replace("%F", Shell.quote(path));
        result = result.replace("%N", Shell.quote(basename));
        result = result.replace("%d", Shell.quote(parent));
        result = result.replace("%D", Shell.quote(parent));

        return result;
    }

    public bool matches_file(string path) {
        if (patterns.length == 0)
            return true;

        var file = File.new_for_path(path);
        string basename = file.get_basename() ?? path;

        foreach (var pattern in patterns) {
            if (pattern == "*")
                return true;
            if (PatternSpec.match_simple(pattern, basename))
                return true;
        }
        return false;
    }
}

public class CustomActionsManager : Object {
    private Gee.ArrayList<CustomAction> actions;

    public CustomActionsManager() {
        actions = new Gee.ArrayList<CustomAction>();
        load_actions();
    }

    public void load_actions() {
        actions.clear();

        string config_dir = Environment.get_user_config_dir();
        string uca_path = Path.build_filename(config_dir, "Thunar", "uca.xml");

        if (!FileUtils.test(uca_path, FileTest.EXISTS)) {
            return;
        }

        try {
            string xml_content;
            FileUtils.get_contents(uca_path, out xml_content);
            parse_xml(xml_content);
        } catch (Error e) {
            warning("Failed to load custom actions from %s: %s", uca_path, e.message);
        }
    }

    private void parse_xml(string xml_content) {
        MarkupParser parser = {
            start_element,
            end_element,
            text_node,
            null,
            null
        };

        MarkupParseContext ctx = new MarkupParseContext(
            parser,
            MarkupParseFlags.TREAT_CDATA_AS_TEXT,
            this,
            null
        );

        try {
            ctx.parse(xml_content, -1);
        } catch (Error e) {
            warning("Failed to parse uca.xml: %s", e.message);
        }
    }

    private CustomAction? current_action = null;
    private string current_element = "";

    private void start_element(
        MarkupParseContext ctx,
        string name,
        string[] attr_names,
        string[] attr_values
    ) throws MarkupError {
        current_element = name;

        if (name == "action") {
            current_action = new CustomAction();
            for (int i = 0; i < attr_names.length; i++) {
                if (attr_names[i] == "id") {
                    current_action.id = attr_values[i];
                }
            }
        }
    }

    private void end_element(MarkupParseContext ctx, string name) throws MarkupError {
        if (name == "action" && current_action != null) {
            if (current_action.id == "") {
                current_action.id = "action_%u".printf(actions.size);
            }
            actions.add(current_action);
            current_action = null;
        }
        current_element = "";
    }

    private void text_node(MarkupParseContext ctx, string text, size_t text_len) throws MarkupError {
        if (current_action == null)
            return;

        string trimmed = text.strip();
        if (trimmed == "")
            return;

        switch (current_element) {
            case "icon":
                current_action.icon = trimmed;
                break;
            case "name":
                current_action.name = trimmed;
                break;
            case "command":
                current_action.command = trimmed;
                break;
            case "description":
                current_action.description = trimmed;
                break;
            case "patterns":
                current_action.patterns = trimmed.split(";");
                break;
            case "directories":
                current_action.on_directories = true;
                break;
            case "audio-files":
            case "image-files":
            case "video-files":
            case "other-files":
            case "text-files":
                current_action.on_files = true;
                break;
        }
    }

    public CustomAction[] get_actions_for_file(string path) {
        var result = new Gee.ArrayList<CustomAction>();
        foreach (var action in actions) {
            if (action.on_files && action.matches_file(path)) {
                result.add(action);
            }
        }
        return result.to_array();
    }

    public CustomAction[] get_actions_for_directory(string path) {
        var result = new Gee.ArrayList<CustomAction>();
        foreach (var action in actions) {
            if (action.on_directories && action.matches_file(path)) {
                result.add(action);
            }
        }
        return result.to_array();
    }

    public CustomAction[] get_all_actions() {
        return actions.to_array();
    }

    public void execute_action(CustomAction action, string path) {
        string cmd = action.build_command(path);
        debug("Executing custom action: %s", cmd);

        try {
            string[] argv = cmd.split(" ");
            var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
            if (Path.get_dirname(path) != "") {
                launcher.set_cwd(Path.get_dirname(path));
            }
            launcher.spawnv (argv);
        } catch (Error e) {
            warning("Failed to execute custom action '%s': %s", action.name, e.message);
        }
    }
}

}
