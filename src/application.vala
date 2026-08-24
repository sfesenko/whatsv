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

[GtkTemplate (ui = "/com/github/sfesenko/whatsv/window.ui")]
public class Whatsv.Window : Gtk.ApplicationWindow {

    public string profile { get; construct; }
    public WebKit.WebView view { get; private set; }

    // Keep session alive for lifetime of window
    private WebKit.NetworkSession? network_session = null;
    private static GLib.HashTable<string, WebKit.NetworkSession>? sessions = null;
    private GLib.Settings app_settings;
    private int64 last_load_finished = 0;
    private bool pending_user_reload = false;

    public Window (Gtk.Application app, string profile = "default") {
        Object (application: app, profile: profile);
    }

    construct {
        // GSettings for window geometry / zoom (wired to gschema keys)
        app_settings = new GLib.Settings ("com.github.sfesenko.whatsv");
        int sw = app_settings.get_int ("window-width");
        int sh = app_settings.get_int ("window-height");
        bool smax = app_settings.get_boolean ("window-maximized");
        this.set_default_size (sw, sh);
        if (smax) this.maximize ();

        // Resolve help overlay from gresource so win.show-help-overlay works
        try {
            var builder = new Gtk.Builder.from_resource ("/com/github/sfesenko/whatsv/gtk/help-overlay.ui");
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
        // Use Chrome-like UA for best compatibility with WhatsApp Web
        // Avoid overriding if server already sets via quirks, but WhatsApp blocks generic WebKit UA
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
        // Allow WhatsApp to use fullscreen for calls
        settings.enable_fullscreen = true;
        view.set_settings (settings);

        // Permissions: WhatsApp needs notifications + media (calls)
        view.permission_request.connect (on_permission_request);

        // Handle target=_blank / window.open — keep main WhatsApp inside, block Flows etc.
        view.create.connect ((nav_action) => {
            var uri = nav_action.get_request ().get_uri ();
            if (uri == null) return (Gtk.Widget?) null;
            if (is_main_whatsapp_uri (uri)) {
                // New window for web.whatsapp.com itself — load in same view
                view.load_uri (uri);
            } else if (is_whatsapp_uri (uri)) {
                // Flows and other WhatsApp subdomains — do not navigate, do not open browser
                warning ("Ignoring create for WhatsApp subresource %s", uri);
            } else {
                // External — open in default browser
                var launcher = new Gtk.UriLauncher (uri);
                launcher.launch.begin (this, null, (obj, res) => {
                    try { launcher.launch.end (res); } catch (Error e) { warning ("Failed to launch %s: %s", uri, e.message); }
                });
            }
            return (Gtk.Widget?) null;
        });
        view.decide_policy.connect (on_decide_policy);

        // Progress / title sync
        view.notify["title"].connect (() => {
            var t = view.title;
            if (t != null && t.strip () != "") {
                this.title = "%s — WhatsV".printf (t);
            } else {
                this.title = "WhatsV";
            }
        });
        view.notify["estimated-load-progress"].connect (() => {
            // Could hook progress indicator in headerbar later
        });
        view.load_failed.connect (on_load_failed);
        view.load_changed.connect (on_load_changed);
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
                    var base_name = Whatsv.Utils.sanitize_download_filename (suggested);
                    var dest = Whatsv.Utils.deduplicate_download_path (downloads, base_name);
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

        this.view.load_uri ("https://web.whatsapp.com");
    }

    private static WebKit.NetworkSession get_or_create_session (string profile) {
        if (sessions == null) {
            sessions = new GLib.HashTable<string, WebKit.NetworkSession> (str_hash, str_equal);
        }
        var existing = sessions.lookup (profile);
        if (existing != null) {
            return existing;
        }

        string data_dir;
        string cache_dir;
        get_dirs_for_profile (profile, out data_dir, out cache_dir);

        // Legacy migration check before creating modern dirs (otherwise cache_dir exists and check is dead)
        if (profile == "default") {
            var legacy_data = Path.build_filename (Environment.get_user_data_dir (), "whatsv");
            bool modern_has_storage = FileUtils.test (Path.build_filename (data_dir, "storage"), FileTest.IS_DIR)
                || FileUtils.test (Path.build_filename (data_dir, "LocalStorage"), FileTest.EXISTS)
                || FileUtils.test (Path.build_filename (data_dir, "IndexedDB"), FileTest.EXISTS);
            if (FileUtils.test (legacy_data, FileTest.IS_DIR) && !modern_has_storage) {
                message ("Legacy session dir %s detected; new profile dir is %s. If your login was lost, copy files manually.", legacy_data, data_dir);
            }
            var legacy_cache = Path.build_filename (Environment.get_user_cache_dir (), "whatsv");
            bool modern_cache_exists = FileUtils.test (cache_dir, FileTest.IS_DIR)
                && FileUtils.test (Path.build_filename (cache_dir, "WebKitCache"), FileTest.IS_DIR);
            // Check before ensure_dir, otherwise cache_dir always exists
            if (FileUtils.test (legacy_cache, FileTest.IS_DIR) && !modern_cache_exists) {
                message ("Legacy cache dir %s detected; new cache dir is %s", legacy_cache, cache_dir);
            }
        }

        // Ensure dirs exist (0700 for privacy) after legacy check
        ensure_dir (data_dir);
        ensure_dir (cache_dir);

        var session = new WebKit.NetworkSession (data_dir, cache_dir);
        // Persist credentials (HSTS etc) and ITP off for messaging
        session.set_persistent_credential_storage_enabled (true);
        // ITP can break WhatsApp; disable
        session.set_itp_enabled (false);

        sessions.insert (profile, session);
        return session;
    }

    private static void get_dirs_for_profile (string profile, out string data_dir, out string cache_dir) {
        var raw = profile.strip ();
        if (raw == "" || raw == "." || raw == "..") raw = "default";
        string safe;
        try {
            // Replace any char not in whitelist with _
            var re = new Regex ("[^A-Za-z0-9._-]");
            safe = re.replace (raw, -1, 0, "_");
            // Avoid hidden files and traversal
            while (safe.has_prefix (".")) safe = safe.substring (1);
            if (safe == "" || safe == "." || safe == "..") safe = "default";
            if (safe.length > 64) {
                var hash = Checksum.compute_for_string (ChecksumType.SHA256, raw);
                safe = safe.substring (0, 32) + "_" + hash.substring (0, 8);
            }
            var ws_re = new Regex ("^[A-Za-z0-9._-]+$");
            if (!ws_re.match (safe)) {
                safe = "profile_" + Checksum.compute_for_string (ChecksumType.SHA256, raw).substring (0, 12);
            }
        } catch (Error e) {
            safe = "default";
        }
        var base_data = Path.build_filename (Environment.get_user_data_dir (), "com.github.sfesenko.whatsv", "profiles", safe);
        var base_cache = Path.build_filename (Environment.get_user_cache_dir (), "com.github.sfesenko.whatsv", "profiles", safe);
        data_dir = base_data;
        cache_dir = base_cache;
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
                // Fallback: ignore, umask may have left 0755
            }
        } catch (Error e) {
            warning ("Failed to create dir %s: %s", path, e.message);
        }
    }

    // --- Window actions ---

    private void on_reload () {
        pending_user_reload = true;
        view.reload ();
    }

    private void on_reload_bypass_cache () {
        pending_user_reload = true;
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
        // Only allow known permissions for WhatsApp origins
        var origin = view.get_uri ();
        bool is_whatsapp = origin != null && (is_main_whatsapp_uri (origin) || is_whatsapp_uri (origin));
        if (!is_whatsapp) {
            warning ("Denying %s for non-WhatsApp origin %s", request.get_type ().name (), origin ?? "(null)");
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

    private bool is_main_whatsapp_uri (string uri) {
        return Whatsv.Utils.is_main_whatsapp_uri (uri);
    }

    private bool is_whatsapp_uri (string uri) {
        return Whatsv.Utils.is_whatsapp_uri (uri);
    }

    private bool on_decide_policy (WebKit.PolicyDecision decision, WebKit.PolicyDecisionType type) {
        if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
            var nav = (WebKit.NavigationPolicyDecision) decision;
            var action = nav.get_navigation_action ();
            var req = action.get_request ();
            var uri = req.get_uri ();
            if (uri == null) {
                decision.use ();
                return true;
            }

            // Only web.whatsapp.com is allowed as top-level navigation inside WebView.
            // Other WhatsApp hosts (flows.whatsapp.net, etc.) are either XHR/subresource
            // or external help links. They must not trigger top-level WebView navigation,
            // otherwise the WhatsApp loading screen appears twice.
            if (is_main_whatsapp_uri (uri)) {
                // WhatsApp Web does an automatic reload ~7s after showing chats
                // (RELOAD navigation) when using a per-profile NetworkSession.
                // Suppress that automatic reload, but allow explicit user reloads via Ctrl+R.
                if (action.get_navigation_type () == WebKit.NavigationType.RELOAD) {
                    if (pending_user_reload) {
                        pending_user_reload = false;
                        decision.use ();
                        return true;
                    }
                    int64 now = GLib.get_monotonic_time ();
                    if (last_load_finished != 0 && (now - last_load_finished) < 15 * 1000 * 1000) {
                        warning ("Suppressing automatic reload for %s (%.1fs after load)", uri, (now - last_load_finished) / 1000000.0);
                        decision.ignore ();
                        return true;
                    }
                }
                decision.use ();
                return true;
            }
            if (is_whatsapp_uri (uri)) {
                // WhatsApp subresource / non-main host
                if (action.get_navigation_type () == WebKit.NavigationType.LINK_CLICKED) {
                    // User clicked a WhatsApp link (e.g. faq) — open externally
                    var launcher = new Gtk.UriLauncher (uri);
                    launcher.launch.begin (this, null, (obj, res) => {
                        try { launcher.launch.end (res); } catch (Error e) { warning ("Failed to launch %s: %s", uri, e.message); }
                    });
                    decision.ignore ();
                    return true;
                } else {
                    // Non-click navigation to flows etc. — silently ignore (was opening browser twice)
                    // Do not use() — that would navigate WebView away from WhatsApp.
                    warning ("Ignoring WhatsApp subresource navigation to %s", uri);
                    decision.ignore ();
                    return true;
                }
            }

            // External http(s): only honor explicit user clicks (LinkClicked).
            // Other navigation types (form, reload, API-driven) are ignored to avoid
            // stray browser popups.
            if (uri.has_prefix ("http://") || uri.has_prefix ("https://")) {
                if (action.get_navigation_type () == WebKit.NavigationType.LINK_CLICKED) {
                    var launcher = new Gtk.UriLauncher (uri);
                    launcher.launch.begin (this, null, (obj, res) => {
                        try {
                            launcher.launch.end (res);
                        } catch (Error e) {
                            warning ("Failed to launch uri %s: %s", uri, e.message);
                        }
                    });
                    decision.ignore ();
                    return true;
                } else {
                    warning ("Ignoring non-click navigation to %s", uri);
                    decision.ignore ();
                    return true;
                }
            }
        } else if (type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
            var nav = (WebKit.NavigationPolicyDecision) decision;
            var uri = nav.get_navigation_action ().get_request ().get_uri ();
            if (uri == null) {
                decision.use ();
                return true;
            }
            if (is_main_whatsapp_uri (uri)) {
                decision.use ();
                return true;
            }
            if (is_whatsapp_uri (uri)) {
                // Flows etc. in new window — ignore
                warning ("Ignoring new-window WhatsApp subresource %s", uri);
                decision.ignore ();
                return true;
            }
            if (uri.has_prefix ("http://") || uri.has_prefix ("https://")) {
                var launcher = new Gtk.UriLauncher (uri);
                launcher.launch.begin (this, null, (obj, res) => {
                    try { launcher.launch.end (res); } catch (Error e) { warning ("Failed to launch %s: %s", uri, e.message); }
                });
                decision.ignore ();
                return true;
            }
        }
        decision.use ();
        return true;
    }

    private bool on_load_failed (WebKit.LoadEvent event, string failing_uri, Error error) {
        warning ("Load failed %s: %s", failing_uri, error.message);
        // Let WebKit show error page; return false to allow default handling
        return false;
    }

    private void on_load_changed (WebKit.LoadEvent event) {
        if (event == WebKit.LoadEvent.FINISHED) {
            last_load_finished = GLib.get_monotonic_time ();
        }
    }
}

public class Whatsv.Application : Gtk.Application {
    private string requested_profile = "default";

    public Application () {
        Object (
            application_id: "com.github.sfesenko.whatsv",
            flags: ApplicationFlags.HANDLES_COMMAND_LINE,
            resource_base_path: "/com/github/sfesenko/whatsv"
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
            var win = w as Whatsv.Window;
            if (win != null && win.profile == this.requested_profile) {
                win.present ();
                return;
            }
        }

        // If profile requested but active window exists with different profile, create new window (single-process multi-window)
        // If no window exists, create default/new profile window
        var win = new Whatsv.Window (this, this.requested_profile);
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
            "program-name", "WhatsV",
            "logo-icon-name", "com.github.sfesenko.whatsv",
            "authors", authors,
            "translator-credits", _("translator-credits"),
            "version", Config.PACKAGE_VERSION,
            "copyright", "© 2025 Sergii Fesenko",
            "license-type", Gtk.License.MIT_X11,
            "website", "https://github.com/sfesenko/whatsv",
            "comments", _("Simple Vala WhatsApp Web Client")
        );
    }
}
