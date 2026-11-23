/* MIT License
 *
 * Copyright (c) 2025 Sergii Fesenko
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 *
 * SPDX-License-Identifier: MIT
 */

[GtkTemplate (ui = "/com/github/sfesenko/webapp/window.ui")]
public class WebApp.Window : Gtk.ApplicationWindow {

    public string profile { get; construct; }
    public WebKit.WebView view { get; private set; }

    // Keep session alive for lifetime of window
    private WebKit.NetworkSession? network_session = null;
    private static GLib.HashTable<string, WebKit.NetworkSession>? sessions = null;
    private GLib.Settings app_settings;

    public Window (Gtk.Application app, string profile = "default") {
        Object (application: app, profile: profile);
    }

    construct {
        // GSettings for window geometry / zoom (wired to gschema keys)
        app_settings = new GLib.Settings (Config.APP_ID);
        int sw = app_settings.get_int ("window-width");
        int sh = app_settings.get_int ("window-height");
        bool smax = app_settings.get_boolean ("window-maximized");
        this.set_default_size (sw, sh);
        if (smax) this.maximize ();

        // Resolve help overlay from gresource so win.show-help-overlay works
        try {
            var builder = new Gtk.Builder.from_resource ("/com/github/sfesenko/webapp/gtk/help-overlay.ui");
            var overlay = builder.get_object ("help_overlay") as Gtk.ShortcutsWindow;
            if (overlay != null) {
                this.set_help_overlay (overlay);
            }
        } catch (Error e) {
            warning ("Failed to load help overlay: %s", e.message);
        }

        // Persist geometry / zoom on close
        this.close_request.connect (on_close_request);

        // Window-level actions (PaperWM/GNOME safe: avoid Super, use Ctrl/Alt local)
        ActionEntry[] win_entries = {
            { "reload", on_reload },
            { "reload-bypass-cache", on_reload_bypass_cache },
            { "zoom-in", on_zoom_in },
            { "zoom-out", on_zoom_out },
            { "zoom-reset", on_zoom_reset },
            { "go-back", on_go_back },
            { "go-forward", on_go_forward },
            { "close-window", on_close_window },
        };
        this.add_action_entries (win_entries, this);

        // Create/obtain persistent NetworkSession for this profile
        this.network_session = get_or_create_session (this.profile);
        // NetworkSession is construct-only: use Object.new with "network-session" property
        this.view = Object.new (typeof (WebKit.WebView), "network-session", this.network_session) as WebKit.WebView;

        // Harden / tweak settings
        var settings = view.get_settings () ?? new WebKit.Settings ();
        // Use Chrome-like UA for best compatibility with modern web apps
        settings.user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";
        settings.enable_developer_extras = false;
        settings.enable_javascript = true;
        settings.enable_media_stream = true;
        settings.enable_mediasource = true;
        settings.enable_webaudio = true;
        settings.enable_webrtc = true;
        settings.enable_smooth_scrolling = true;
        settings.enable_page_cache = false;
        settings.enable_html5_local_storage = true;
        settings.enable_html5_database = true;
        // Allow the site to use fullscreen for calls
        settings.enable_fullscreen = true;
        view.set_settings (settings);

        // Permissions: the site needs notifications + media (calls)
        view.permission_request.connect (on_permission_request);

        // Handle target=_blank / window.open — keep the site inside, block subresources
        view.create.connect ((nav_action) => {
            var uri = nav_action.get_request ().get_uri ();
            if (uri == null) return (Gtk.Widget?) null;
            switch (WebApp.Utils.decide_navigation (uri, Config.SITE_HOSTS, false, true)) {
                case WebApp.Utils.NavigationDisposition.IN_VIEW:
                    view.load_uri (uri);
                    break;
                case WebApp.Utils.NavigationDisposition.OPEN_EXTERNAL:
                    open_external (uri);
                    break;
                default:
                    warning ("Ignoring create for subresource %s", uri);
                    break;
            }
            return (Gtk.Widget?) null;
        });
        view.decide_policy.connect (on_decide_policy);

        // Progress / title sync
        view.notify["title"].connect (() => {
            var t = view.title;
            if (t != null && t.strip () != "") {
                this.title = "%s — %s".printf (t, Config.APP_NAME);
            } else {
                this.title = Config.APP_NAME;
            }
        });
        view.notify["estimated-load-progress"].connect (() => {
            // Could hook progress indicator in headerbar later
        });
        view.load_failed.connect (on_load_failed);
        view.notify["is-loading"].connect (() => {
            // placeholder for spinner
        });

        // Restore zoom from GSettings before first load to avoid double paint/reload
        double zlevel = app_settings.get_double ("zoom-level");
        if (zlevel < 0.3) zlevel = 0.3;
        if (zlevel > 3.0) zlevel = 3.0;
        view.zoom_level = zlevel;
        view.notify["zoom-level"].connect (() => {
            app_settings.set_double ("zoom-level", view.zoom_level);
        });

        // Downloads: use XDG Downloads folder, sanitized via Utils
        if (this.network_session != null) {
            this.network_session.download_started.connect ((dl) => {
                dl.decide_destination.connect ((suggested) => {
                    var downloads = Environment.get_user_special_dir (UserDirectory.DOWNLOAD);
                    if (downloads == null) downloads = Environment.get_home_dir ();
                    var base_name = WebApp.Utils.sanitize_download_filename (suggested);
                    var dest = WebApp.Utils.deduplicate_download_path (downloads, base_name);
                    dl.set_destination (dest);
                    dl.set_allow_overwrite (false);
                    return true;
                });
                var req_uri = dl.get_request () != null ? dl.get_request ().get_uri () : "(null)";
                message ("Download started: %s", req_uri);
                dl.failed.connect ((err) => {
                    warning ("Download failed: %s", err.message);
                });
                dl.finished.connect (() => {
                    message ("Download finished: %s", dl.get_destination ());
                });
            });
        }

        this.set_child (view);

        // Apply profile to window title tooltip for multi-profile distinction
        if (this.profile != "default") {
            this.tooltip_text = "Profile: %s".printf (this.profile);
        }

        this.view.load_uri (Config.SITE_START_URL);
    }

    private static WebKit.NetworkSession get_or_create_session (string profile) {
        if (Config.EPHEMERAL) {
            return new WebKit.NetworkSession.ephemeral ();
        }
        if (sessions == null) {
            sessions = new GLib.HashTable<string, WebKit.NetworkSession> (str_hash, str_equal);
        }
        var existing = sessions.lookup (profile);
        if (existing != null) {
            return existing;
        }

        string data_dir;
        string cache_dir;
        WebApp.Utils.get_dirs_for_profile (profile, Config.APP_ID, Config.DATA_DIR_ROOT, Config.CACHE_DIR_ROOT, out data_dir, out cache_dir);

        // Ensure dirs exist (0700 for privacy)
        ensure_dir (data_dir);
        ensure_dir (cache_dir);

        var session = new WebKit.NetworkSession (data_dir, cache_dir);
        // Persist credentials (HSTS etc) and ITP off for messaging
        session.set_persistent_credential_storage_enabled (true);
        // ITP can break single-page apps; disable
        session.set_itp_enabled (false);

        sessions.insert (profile, session);
        return session;
    }

    private static void ensure_dir (string path) {
        try {
            var f = File.new_for_path (path);
            if (!f.query_exists ()) {
                f.make_directory_with_parents ();
            }
            // Ensure 0700 regardless of umask
            try {
                var info = new FileInfo ();
                info.set_attribute_uint32 (FileAttribute.UNIX_MODE, 0700);
                f.set_attributes_from_info (info, FileQueryInfoFlags.NONE);
            } catch (Error e) {
                warning ("Failed to set mode 0700 on %s: %s", path, e.message);
            }
        } catch (Error e) {
            warning ("Failed to create dir %s: %s", path, e.message);
        }
    }

    private void open_external (string uri) {
        var launcher = new Gtk.UriLauncher (uri);
        launcher.launch.begin (this, null, (obj, res) => {
            try {
                launcher.launch.end (res);
            } catch (Error e) {
                warning ("Failed to launch %s: %s", uri, e.message);
            }
        });
    }

    // --- Window actions ---

    private void on_reload () {
        view.reload ();
    }

    private void on_reload_bypass_cache () {
        view.reload_bypass_cache ();
    }

    private void on_zoom_in () {
        view.zoom_level = double.min (3.0, view.zoom_level + 0.1);
    }

    private void on_zoom_out () {
        view.zoom_level = double.max (0.3, view.zoom_level - 0.1);
    }

    private void on_zoom_reset () {
        view.zoom_level = 1.0;
    }

    private void on_go_back () {
        if (view.can_go_back ()) view.go_back ();
    }

    private void on_go_forward () {
        if (view.can_go_forward ()) view.go_forward ();
    }

    private void on_close_window () {
        this.close ();
    }

    private bool on_close_request () {
        bool is_max = this.maximized;
        bool is_full = this.fullscreened;
        // Store maximized (and fullscreen as maximized for now; gschema has no fullscreen key)
        app_settings.set_boolean ("window-maximized", is_max || is_full);
        if (!is_max && !is_full) {
            // Use allocated size, not get_default_size which returns the value set via set_default_size
            int cw = this.get_width ();
            int ch = this.get_height ();
            if (cw > 0 && ch > 0) {
                app_settings.set_int ("window-width", cw);
                app_settings.set_int ("window-height", ch);
            }
        }
        app_settings.set_double ("zoom-level", view.zoom_level);
        return false;
    }

    // --- WebKit signals ---

    private bool on_permission_request (WebKit.PermissionRequest request) {
        // Only allow known permissions for configured site origins
        var origin = view.get_uri ();
        bool is_site = WebApp.Utils.is_allowed_host (origin ?? "", Config.SITE_HOSTS);
        if (!is_site) {
            warning ("Denying %s for untrusted origin %s", request.get_type ().name (), origin ?? "(null)");
            request.deny ();
            return true;
        }
        if (request is WebKit.NotificationPermissionRequest) {
            request.allow ();
            return true;
        }
        if (request is WebKit.UserMediaPermissionRequest) {
            request.allow ();
            return true;
        }
        if (request is WebKit.MediaKeySystemPermissionRequest) {
            request.allow ();
            return true;
        }
        if (request is WebKit.WebsiteDataAccessPermissionRequest) {
            request.allow ();
            return true;
        }
        if (request is WebKit.DeviceInfoPermissionRequest) {
            request.allow ();
            return true;
        }
        message ("Unhandled permission request: %s -> deny", request.get_type ().name ());
        request.deny ();
        return true;
    }

    private bool on_decide_policy (WebKit.PolicyDecision decision, WebKit.PolicyDecisionType type) {
        if (type != WebKit.PolicyDecisionType.NAVIGATION_ACTION
                && type != WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
            decision.use ();
            return true;
        }
        var nav = decision as WebKit.NavigationPolicyDecision;
        if (nav == null) {
            decision.use ();
            return true;
        }
        var action = nav.get_navigation_action ();
        var uri = action.get_request ().get_uri ();
        if (uri == null) {
            decision.use ();
            return true;
        }

        bool is_link_clicked = action.get_navigation_type () == WebKit.NavigationType.LINK_CLICKED;
        bool is_new_window = type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION;
        switch (WebApp.Utils.decide_navigation (uri, Config.SITE_HOSTS, is_link_clicked, is_new_window)) {
            case WebApp.Utils.NavigationDisposition.IN_VIEW:
                decision.use ();
                break;
            case WebApp.Utils.NavigationDisposition.OPEN_EXTERNAL:
                open_external (uri);
                decision.ignore ();
                break;
            default:
                warning ("Ignoring navigation to %s", uri);
                decision.ignore ();
                break;
        }
        return true;
    }

    private bool on_load_failed (WebKit.LoadEvent event, string failing_uri, Error error) {
        warning ("Load failed %s: %s", failing_uri, error.message);
        // Let WebKit show error page; return false to allow default handling
        return false;
    }
}

public class WebApp.Application : Gtk.Application {
    private string requested_profile = "default";

    public Application () {
        Object (
            application_id: Config.APP_ID,
            flags: ApplicationFlags.HANDLES_COMMAND_LINE,
            resource_base_path: "/com/github/sfesenko/webapp"
        );
    }

    construct {
        this.add_main_option ("profile", 'p', OptionFlags.NONE, OptionArg.STRING, "Use profile NAME (isolated session)", "NAME");

        ActionEntry[] action_entries = {
            { "about", this.on_about_action },
            { "quit", this.quit }
        };
        this.add_action_entries (action_entries, this);

        // App-level accelerators (PaperWM/GNOME safe: only Ctrl/Alt+F-keys, no Super)
        this.set_accels_for_action ("app.quit", {"<primary>q"});
        // Window actions — set globally but apply to active win
        this.set_accels_for_action ("win.reload", {"<primary>r", "F5"});
        this.set_accels_for_action ("win.reload-bypass-cache", {"<primary><shift>r", "<primary>F5"});
        this.set_accels_for_action ("win.zoom-in", {"<primary>plus", "<primary>equal", "<primary>KP_Add"});
        this.set_accels_for_action ("win.zoom-out", {"<primary>minus", "<primary>KP_Subtract"});
        this.set_accels_for_action ("win.zoom-reset", {"<primary>0", "<primary>KP_0"});
        // Go back/forward: Alt+Left/Right is browser std; add Ctrl+[ / Ctrl+] as PaperWM-friendly alt (no Alt)
        this.set_accels_for_action ("win.go-back", {"<alt>Left", "<primary>bracketleft"});
        this.set_accels_for_action ("win.go-forward", {"<alt>Right", "<primary>bracketright"});
        this.set_accels_for_action ("win.close-window", {"<primary>w"});
        // Help overlay: F1 is standard; Ctrl+? (Ctrl+Shift+/) non-conflicting
        this.set_accels_for_action ("win.show-help-overlay", {"F1", "<primary>question"});
    }

    protected override int handle_local_options (VariantDict options) {
        if (options.contains ("profile")) {
            string p = "";
            if (options.lookup_value ("profile", VariantType.STRING) != null) {
                p = options.lookup_value ("profile", VariantType.STRING).get_string ();
                if (p.strip () != "") {
                    this.requested_profile = p.strip ();
                }
            }
        }
        return -1; // continue normal processing
    }

    public override int command_line (ApplicationCommandLine command_line) {
        var opts = command_line.get_options_dict ();
        Variant? v = opts.lookup_value ("profile", VariantType.STRING);
        if (v != null) {
            var p = v.get_string ().strip ();
            if (p != "") this.requested_profile = p;
        }
        // Also handle remaining args as profile positional? ignore
        this.activate ();
        return 0;
    }

    public override void activate () {
        base.activate ();

        // Search existing window with same profile — present it
        foreach (var w in this.get_windows ()) {
            var win = w as WebApp.Window;
            if (win != null && win.profile == this.requested_profile) {
                win.present ();
                return;
            }
        }

        // If profile requested but active window exists with different profile, create new window (single-process multi-window)
        // If no window exists, create default/new profile window
        var win = new WebApp.Window (this, this.requested_profile);
        win.present ();
    }

    public override void open (File[] files, string hint) {
        // File opening not supported; just activate
        this.activate ();
    }

    private void on_about_action () {
        string[] authors = { "Sergii Fesenko" };
        Gtk.show_about_dialog (
            this.active_window,
            "program-name", Config.APP_NAME,
            "logo-icon-name", Config.APP_ID,
            "authors", authors,
            "translator-credits", _("translator-credits"),
            "version", Config.PACKAGE_VERSION,
            "copyright", "© 2025 Sergii Fesenko",
            "license-type", Gtk.License.MIT_X11,
            "website", "https://github.com/sfesenko/whatsv",
            "comments", _("Simple %s web client").printf (Config.APP_NAME)
        );
    }
}
