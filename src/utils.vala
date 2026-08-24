/* Whatsv.Utils — pure helpers extracted for unit testing
 * SPDX-License-Identifier: MIT
 */

namespace Whatsv.Utils {

    public bool is_main_whatsapp_uri (string uri) {
        try {
            var guri = GLib.Uri.parse (uri, GLib.UriFlags.NONE);
            var host = guri.get_host ();
            if (host == null) return false;
            return host.down () == "web.whatsapp.com";
        } catch (Error e) {
            return uri.has_prefix ("https://web.whatsapp.com");
        }
    }

    public bool is_whatsapp_uri (string uri) {
        try {
            var guri = GLib.Uri.parse (uri, GLib.UriFlags.NONE);
            var host = guri.get_host ();
            if (host == null) return false;
            host = host.down ();
            return host == "web.whatsapp.com"
                || host == "whatsapp.com"
                || host == "whatsapp.net"
                || host.has_suffix (".whatsapp.com")
                || host.has_suffix (".whatsapp.net")
                || host.has_suffix (".fbcdn.net")
                || host.has_suffix (".facebook.com")
                || host == "flows.whatsapp.net";
        } catch (Error e) {
            return uri.contains ("whatsapp.com") || uri.contains ("whatsapp.net") || uri.contains ("fbcdn.net");
        }
    }

    public string sanitize_profile_name (string profile) {
        var raw = profile.strip ();
        if (raw == "" || raw == "." || raw == "..") raw = "default";
        string safe;
        try {
            var re = new Regex ("[^A-Za-z0-9._-]");
            safe = re.replace (raw, -1, 0, "_");
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
        return safe;
    }

    public void get_dirs_for_profile (string profile, out string data_dir, out string cache_dir) {
        string safe = sanitize_profile_name (profile);
        var base_data = Path.build_filename (Environment.get_user_data_dir (), "com.github.sfesenko.whatsv", "profiles", safe);
        var base_cache = Path.build_filename (Environment.get_user_cache_dir (), "com.github.sfesenko.whatsv", "profiles", safe);
        data_dir = base_data;
        cache_dir = base_cache;
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
        if (base_name.length > 255) base_name = base_name.substring (0, 255);
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
            var candidate = "%s (%d)%s".printf (stem, n, ext);
            dest = Path.build_filename (downloads_dir, candidate);
            file = File.new_for_path (dest);
            n++;
            if (n > 100) break;
        }
        return dest;
    }
}
