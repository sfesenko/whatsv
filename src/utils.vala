/* WebApp.Utils — pure helpers extracted for unit testing
 * SPDX-License-Identifier: MIT
 */

namespace WebApp.Utils {

    public enum NavigationDisposition {
        IN_VIEW,
        OPEN_EXTERNAL,
        IGNORE
    }

    private string? scheme_of (string uri) {
        int colon = uri.index_of (":");
        if (colon <= 0) return null;
        return uri.substring (0, colon).down ();
    }

    private string? extract_host_from_string (string uri) {
        var low = uri.strip ().down ();
        int offset;
        if (low.has_prefix ("https://")) {
            offset = 8;
        } else if (low.has_prefix ("http://")) {
            offset = 7;
        } else {
            return null;
        }
        var rest = low.substring (offset);
        int end = rest.length;
        int slash = rest.index_of ("/");
        if (slash >= 0 && slash < end) end = slash;
        int query = rest.index_of ("?");
        if (query >= 0 && query < end) end = query;
        int fragment = rest.index_of ("#");
        if (fragment >= 0 && fragment < end) end = fragment;
        var authority = rest.substring (0, end);
        int at = authority.last_index_of ("@");
        if (at >= 0) authority = authority.substring (at + 1);
        if (authority.has_prefix ("[")) {
            int close = authority.index_of ("]");
            if (close <= 1) return null;
            authority = authority.substring (1, close - 1);
        } else {
            int colon = authority.index_of (":");
            if (colon >= 0) authority = authority.substring (0, colon);
        }
        authority = authority.strip ();
        if (authority == "") return null;
        return authority;
    }

    private string? extract_host (string uri) {
        try {
            var guri = GLib.Uri.parse (uri.strip (), GLib.UriFlags.NONE);
            var host = guri.get_host ();
            if (host == null || host == "") return null;
            return host.down ();
        } catch (Error e) {
            return extract_host_from_string (uri);
        }
    }

    private bool host_is_single_label (string host) {
        return !host.contains (".") && !host.contains (":");
    }

    private bool host_is_ipv4_literal (string host) {
        if (!host.contains (".")) return false;
        for (int i = 0; i < host.length; i++) {
            char c = host[i];
            if (c != '.' && (c < '0' || c > '9')) return false;
        }
        return true;
    }

    public bool is_allowed_host (string uri, string allowed_hosts) {
        var host = extract_host (uri);
        if (host == null) return false;
        int start = 0;
        while (true) {
            int comma = allowed_hosts.index_of (",", start);
            string entry = comma < 0 ? allowed_hosts.substring (start) : allowed_hosts.substring (start, comma - start);
            var candidate = entry.strip ().down ();
            if (candidate.has_prefix (".")) candidate = candidate.substring (1);
            if (candidate.has_prefix ("[") && candidate.has_suffix ("]")) {
                candidate = candidate.substring (1, candidate.length - 2);
            }
            bool suffix_match = !host_is_single_label (candidate)
                && !host_is_ipv4_literal (candidate);
            if (candidate != "" && (host == candidate || (suffix_match && host.has_suffix ("." + candidate)))) return true;
            if (comma < 0) break;
            start = comma + 1;
        }
        return false;
    }

    public bool is_benign_scheme (string uri) {
        var scheme = scheme_of (uri);
        return scheme == "about" || scheme == "data" || scheme == "blob" || scheme == "webkit";
    }

    public NavigationDisposition decide_navigation (string uri, string allowed_hosts, bool is_link_clicked, bool is_new_window) {
        var scheme = scheme_of (uri);
        bool is_http = scheme == "http" || scheme == "https";
        if (is_http && is_allowed_host (uri, allowed_hosts)) return NavigationDisposition.IN_VIEW;
        if (is_benign_scheme (uri)) return NavigationDisposition.IN_VIEW;
        if ((scheme == "mailto" || scheme == "tel") && (is_link_clicked || is_new_window)) return NavigationDisposition.OPEN_EXTERNAL;
        if (is_http && (is_link_clicked || is_new_window)) return NavigationDisposition.OPEN_EXTERNAL;
        return NavigationDisposition.IGNORE;
    }

    public enum PermissionDisposition {
        ALLOW,
        DENY,
        PROMPT
    }

    public PermissionDisposition decide_permission (string request_type, bool site_trusted) {
        if (!site_trusted) return PermissionDisposition.DENY;
        switch (request_type) {
            case "WebKitNotificationPermissionRequest":
            case "WebKitMediaKeySystemPermissionRequest":
            case "WebKitDeviceInfoPermissionRequest":
                return PermissionDisposition.ALLOW;
            case "WebKitUserMediaPermissionRequest":
                // Camera, microphone and display capture need an explicit
                // user decision rather than a silent grant.
                return PermissionDisposition.PROMPT;
            default:
                return PermissionDisposition.DENY;
        }
    }

    public string sanitize_profile_name (string profile) {
        var raw = profile.strip ();
        if (raw == "" || raw == "." || raw == "..") raw = "default";
        string safe;
        try {
            var valid_re = new Regex ("^[A-Za-z0-9._-]+$");
            if (raw.length <= 64 && !raw.has_prefix (".") && valid_re.match (raw)) {
                // Already a safe name: keep it stable so sanitizing twice does
                // not change the profile directory.
                return raw;
            }
            var re = new Regex ("[^A-Za-z0-9._-]");
            safe = re.replace (raw, -1, 0, "_");
            while (safe.has_prefix (".")) safe = safe.substring (1);
            if (safe == "" || safe == "." || safe == "..") safe = "default";
            bool lossy = safe != raw;
            if (safe.length > 48) {
                safe = safe.substring (0, 48);
                lossy = true;
            }
            if (lossy) {
                var hash = Checksum.compute_for_string (ChecksumType.SHA256, raw);
                safe += "_" + hash.substring (0, 8);
            }
            var ws_re = new Regex ("^[A-Za-z0-9._-]+$");
            if (!ws_re.match (safe)) {
                safe = "profile_" + Checksum.compute_for_string (ChecksumType.SHA256, raw).substring (0, 12);
            }
        } catch (Error e) {
            safe = "default";
        }
        return safe;
    }

    public void get_dirs_for_profile (string profile, string app_id, string data_root, string cache_root, out string data_dir, out string cache_dir) {
        string safe = sanitize_profile_name (profile);
        var base_data = data_root != "" ? data_root : Environment.get_user_data_dir ();
        var base_cache = cache_root != "" ? cache_root : Environment.get_user_cache_dir ();
        data_dir = Path.build_filename (base_data, app_id, "profiles", safe);
        cache_dir = Path.build_filename (base_cache, app_id, "profiles", safe);
    }

    public string sanitize_download_filename (string suggested) {
        var base_name = Path.get_basename (suggested);
        if (base_name == null || base_name.strip () == "" || base_name == "." || base_name == "..") {
            base_name = "download";
        }
        try {
            var regex = new Regex ("[^A-Za-z0-9._-]");
            base_name = regex.replace (base_name, -1, 0, "_");
        } catch (Error e) {
            base_name = base_name.replace ("/", "_").replace ("\\", "_");
        }
        if (base_name.length > 255) {
            var dot = base_name.last_index_of_char ('.');
            string ext = "";
            if (dot > 0 && base_name.length - dot <= 20) ext = base_name.substring (dot);
            int max_stem = 255 - ext.length;
            if (max_stem < 1) max_stem = 1;
            base_name = base_name.substring (0, max_stem) + ext;
        }
        if (base_name == "" || base_name == "." || base_name == "..") base_name = "download";
        return base_name;
    }

    public string deduplicate_download_path (string downloads_dir, string base_name) {
        var dest = Path.build_filename (downloads_dir, base_name);
        var file = File.new_for_path (dest);
        int n = 1;
        while (file.query_exists ()) {
            var dot = base_name.last_index_of_char ('.');
            string stem;
            string ext = "";
            if (dot > 0) {
                stem = base_name.substring (0, dot);
                ext = base_name.substring (dot);
            } else {
                stem = base_name;
            }
            var suffix = " (%d)%s".printf (n, ext);
            int max_stem = 255 - suffix.length;
            if (max_stem < 1) max_stem = 1;
            if (stem.length > max_stem) stem = stem.substring (0, max_stem);
            var candidate = stem + suffix;
            dest = Path.build_filename (downloads_dir, candidate);
            file = File.new_for_path (dest);
            n++;
            if (n > 100) break;
        }
        return dest;
    }
}
