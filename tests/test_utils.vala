using WebApp.Utils;

const string TEST_HOSTS = "example.com,api.example.com";
const string TEST_APP_ID = "com.example.app";

void test_is_allowed_host () {
    // exact and subdomain matches, case-insensitive
    GLib.assert_true (is_allowed_host ("https://example.com/", TEST_HOSTS));
    GLib.assert_true (is_allowed_host ("https://EXAMPLE.COM/", TEST_HOSTS));
    GLib.assert_true (is_allowed_host ("https://example.com/?ref=chat", TEST_HOSTS));
    GLib.assert_true (is_allowed_host ("https://chat.example.com/", TEST_HOSTS));
    GLib.assert_true (is_allowed_host ("https://api.example.com/login", TEST_HOSTS));
    // a leading dot is ignored
    GLib.assert_true (is_allowed_host ("https://chat.example.com/", ".example.com"));
    // hosts not covered by the list are rejected
    GLib.assert_true (!is_allowed_host ("https://faq.example.net/", TEST_HOSTS));
    // lookalikes and query tricks must not match
    GLib.assert_true (!is_allowed_host ("https://example.com.evil.com/", TEST_HOSTS));
    GLib.assert_true (!is_allowed_host ("https://evil.com/?x=example.com", TEST_HOSTS));
    GLib.assert_true (!is_allowed_host ("https://notexample.com/", TEST_HOSTS));
    // single-label and IPv4 entries only match exactly, never as suffixes
    GLib.assert_true (!is_allowed_host ("https://example.com/", "com"));
    GLib.assert_true (is_allowed_host ("https://com/", "com"));
    GLib.assert_true (!is_allowed_host ("https://127.0.0.1/", "0.0.1"));
    GLib.assert_true (is_allowed_host ("https://127.0.0.1/", "127.0.0.1"));
    // IPv6 literals are bracketed in config but unbracketed by GLib.Uri
    GLib.assert_true (is_allowed_host ("https://[::1]/", "[::1]"));
    // unparseable URI falls back to the string check and finds no allowed host
    GLib.assert_true (!is_allowed_host ("https://exa%mple.com/", TEST_HOSTS));
}

void test_is_benign_scheme () {
    GLib.assert_true (is_benign_scheme ("about:blank"));
    GLib.assert_true (is_benign_scheme ("data:text/plain,hi"));
    GLib.assert_true (is_benign_scheme ("blob:https://example.com/x"));
    GLib.assert_true (is_benign_scheme ("webkit:something"));
    GLib.assert_true (!is_benign_scheme ("https://example.com/"));
    GLib.assert_true (!is_benign_scheme ("ftp://example.com/"));
    GLib.assert_true (!is_benign_scheme ("not a uri"));
}

void test_decide_navigation () {
    // same-origin SPA routes stay in the view, clicked or not
    GLib.assert_true (decide_navigation ("https://example.com/chat", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    GLib.assert_true (decide_navigation ("https://example.com/chat", TEST_HOSTS, true, false) == NavigationDisposition.IN_VIEW);
    // benign internal schemes stay in the view
    GLib.assert_true (decide_navigation ("about:blank", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    GLib.assert_true (decide_navigation ("data:text/plain,hi", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    GLib.assert_true (decide_navigation ("blob:https://example.com/x", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    GLib.assert_true (decide_navigation ("webkit:something", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    // external links are handed to the browser when clicked or opened in a new window
    GLib.assert_true (decide_navigation ("https://other.example/", TEST_HOSTS, true, false) == NavigationDisposition.OPEN_EXTERNAL);
    GLib.assert_true (decide_navigation ("https://other.example/", TEST_HOSTS, false, true) == NavigationDisposition.OPEN_EXTERNAL);
    // non-click external navigations and unknown schemes are ignored
    GLib.assert_true (decide_navigation ("https://other.example/", TEST_HOSTS, false, false) == NavigationDisposition.IGNORE);
    GLib.assert_true (decide_navigation ("ftp://example.com/", TEST_HOSTS, false, false) == NavigationDisposition.IGNORE);
    // mail/tel links are handed to the desktop when the user activates them
    GLib.assert_true (decide_navigation ("mailto:user@example.com", TEST_HOSTS, true, false) == NavigationDisposition.OPEN_EXTERNAL);
    GLib.assert_true (decide_navigation ("tel:+123456", TEST_HOSTS, false, true) == NavigationDisposition.OPEN_EXTERNAL);
    GLib.assert_true (decide_navigation ("mailto:user@example.com", TEST_HOSTS, false, false) == NavigationDisposition.IGNORE);
}

void test_decide_permission () {
    // trusted sites get non-invasive permissions silently
    GLib.assert_true (decide_permission ("WebKitNotificationPermissionRequest", true) == PermissionDisposition.ALLOW);
    GLib.assert_true (decide_permission ("WebKitMediaKeySystemPermissionRequest", true) == PermissionDisposition.ALLOW);
    GLib.assert_true (decide_permission ("WebKitDeviceInfoPermissionRequest", true) == PermissionDisposition.ALLOW);
    // camera/microphone always requires a user decision
    GLib.assert_true (decide_permission ("WebKitUserMediaPermissionRequest", true) == PermissionDisposition.PROMPT);
    // cross-site data access, geolocation and unknown requests are denied
    GLib.assert_true (decide_permission ("WebKitWebsiteDataAccessPermissionRequest", true) == PermissionDisposition.DENY);
    GLib.assert_true (decide_permission ("WebKitGeolocationPermissionRequest", true) == PermissionDisposition.DENY);
    GLib.assert_true (decide_permission ("SomethingElse", true) == PermissionDisposition.DENY);
    // untrusted origins never get anything
    GLib.assert_true (decide_permission ("WebKitNotificationPermissionRequest", false) == PermissionDisposition.DENY);
    GLib.assert_true (decide_permission ("WebKitUserMediaPermissionRequest", false) == PermissionDisposition.DENY);
}

void test_sanitize_profile_name () {
    GLib.assert_true (sanitize_profile_name ("") == "default");
    GLib.assert_true (sanitize_profile_name ("   ") == "default");
    GLib.assert_true (sanitize_profile_name (".") == "default");
    GLib.assert_true (sanitize_profile_name ("..") == "default");
    GLib.assert_true (sanitize_profile_name ("work") == "work");
    GLib.assert_true (sanitize_profile_name ("my-profile") == "my-profile");
    GLib.assert_true (sanitize_profile_name ("a_b") == "a_b");
    GLib.assert_true (sanitize_profile_name ("my profile").has_prefix ("my_profile_"));
    GLib.assert_true (sanitize_profile_name ("a/b\\c").has_prefix ("a_b_c_"));
    GLib.assert_true (sanitize_profile_name (".hidden").has_prefix ("hidden_"));
    // traversal
    GLib.assert_true (sanitize_profile_name ("../etc").has_prefix ("_etc_"));
    // lossy sanitization must not collapse distinct profiles
    GLib.assert_true (sanitize_profile_name ("a/b") != sanitize_profile_name ("a_b"));
    GLib.assert_true (sanitize_profile_name ("日本語") != sanitize_profile_name ("中文版"));
    // long (>64) should be truncated/hashed, still within limit and matches whitelist
    string long = "";
    for (int i = 0; i < 100; i++) long += "a";
    string s = sanitize_profile_name (long);
    GLib.assert_true (s.length <= 64);
    GLib.assert_true (s.length > 0);
    // sanitization must be stable when applied to its own output
    GLib.assert_true (sanitize_profile_name (s) == s);
    GLib.assert_true (sanitize_profile_name (sanitize_profile_name ("my profile")) == sanitize_profile_name ("my profile"));
    // already-safe names up to the limit are preserved unchanged
    string medium = "";
    for (int i = 0; i < 60; i++) medium += "b";
    GLib.assert_true (sanitize_profile_name (medium) == medium);
    try {
        var re = new Regex ("^[A-Za-z0-9._-]+$");
        GLib.assert_true (re.match (s));
    } catch (Error e) { GLib.assert_not_reached (); }
    // unicode and special
    string u = sanitize_profile_name ("профіль");
    GLib.assert_true (u != "" && u != "." && u != "..");
    try {
        var re2 = new Regex ("^[A-Za-z0-9._-]+$");
        GLib.assert_true (re2.match (u));
    } catch (Error e) { GLib.assert_not_reached (); }
}

void test_get_dirs_for_profile () {
    string data, cache;
    get_dirs_for_profile ("work", TEST_APP_ID, "", "", out data, out cache);
    GLib.assert_true (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "work"));
    GLib.assert_true (cache == Path.build_filename (Environment.get_user_cache_dir (), TEST_APP_ID, "profiles", "work"));
    // both roots are sensitive: traversal is sanitized in each
    get_dirs_for_profile ("../etc/passwd", TEST_APP_ID, "", "", out data, out cache);
    GLib.assert_true (!data.contains ("../"));
    GLib.assert_true (!data.has_suffix ("/etc/passwd"));
    GLib.assert_true (!cache.contains ("../"));
    GLib.assert_true (!cache.has_suffix ("/etc/passwd"));
    get_dirs_for_profile ("default", TEST_APP_ID, "", "", out data, out cache);
    GLib.assert_true (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "default"));
    GLib.assert_true (cache == Path.build_filename (Environment.get_user_cache_dir (), TEST_APP_ID, "profiles", "default"));
    // empty profile sanitizes to default
    get_dirs_for_profile ("", TEST_APP_ID, "", "", out data, out cache);
    GLib.assert_true (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "default"));
    // explicit roots replace the XDG roots verbatim for both data and cache
    get_dirs_for_profile ("work", TEST_APP_ID, "/tmp/site-data", "/tmp/site-cache", out data, out cache);
    GLib.assert_true (data == Path.build_filename ("/tmp/site-data", TEST_APP_ID, "profiles", "work"));
    GLib.assert_true (cache == Path.build_filename ("/tmp/site-cache", TEST_APP_ID, "profiles", "work"));
    // long names use exactly the same sanitized component as the session key
    string long_profile = "";
    for (int i = 0; i < 100; i++) long_profile += "c";
    get_dirs_for_profile (long_profile, TEST_APP_ID, "/tmp/site-data", "/tmp/site-cache", out data, out cache);
    GLib.assert_true (data.has_suffix ("/profiles/" + sanitize_profile_name (long_profile)));
    GLib.assert_true (cache.has_suffix ("/profiles/" + sanitize_profile_name (long_profile)));
}

void test_config_constants () {
    // Generated constants must describe a usable configuration: the start URL
    // is allowed, and profile directories follow the configured app id/roots.
    GLib.assert_true (is_allowed_host (Config.SITE_START_URL, Config.SITE_HOSTS));
    string data, cache;
    get_dirs_for_profile ("work", Config.APP_ID, Config.DATA_DIR_ROOT, Config.CACHE_DIR_ROOT, out data, out cache);
    GLib.assert_true (data.has_prefix (Config.DATA_DIR_ROOT != "" ? Config.DATA_DIR_ROOT : Environment.get_user_data_dir ()));
    GLib.assert_true (cache.has_prefix (Config.CACHE_DIR_ROOT != "" ? Config.CACHE_DIR_ROOT : Environment.get_user_cache_dir ()));
    GLib.assert_true (data.contains ("/" + Config.APP_ID + "/profiles/work"));
    GLib.assert_true (cache.contains ("/" + Config.APP_ID + "/profiles/work"));
}

void test_sanitize_download_filename () {
    GLib.assert_true (sanitize_download_filename ("foo.pdf") == "foo.pdf");
    GLib.assert_true (sanitize_download_filename ("a/b/c.pdf") == "c.pdf");
    GLib.assert_true (sanitize_download_filename ("../.bashrc") == ".bashrc");
    // basename handling
    GLib.assert_true (sanitize_download_filename ("") == "download");
    GLib.assert_true (sanitize_download_filename (".") == "download");
    GLib.assert_true (sanitize_download_filename ("..") == "download");
    // unsafe chars replaced
    string s = sanitize_download_filename ("a/b\\c:d*e?f\"g<h>i|j.pdf");
    try {
        var re = new Regex ("^[A-Za-z0-9._-]+$");
        GLib.assert_true (re.match (s));
    } catch (Error e) { GLib.assert_not_reached (); }
    // long
    string long = "";
    for (int i = 0; i < 300; i++) long += "a";
    long += ".pdf";
    string l = sanitize_download_filename (long);
    GLib.assert_true (l.length <= 255);
    GLib.assert_true (l.has_suffix (".pdf") || l.length == 255);
}

void test_deduplicate_download_path () {
    // Use tmp dir
    string tmp = Environment.get_tmp_dir () + "/webapp-test-%d".printf (Random.int_range (0, 1000000));
    DirUtils.create_with_parents (tmp, 0755);
    // create existing file
    string base_name = "file.pdf";
    string p1 = Path.build_filename (tmp, base_name);
    try { FileUtils.set_contents (p1, "x"); } catch (Error e) {}
    string dest = deduplicate_download_path (tmp, base_name);
    GLib.assert_true (dest != p1);
    GLib.assert_true (dest.contains ("(1)"));
    // second dedup should give (2) if (1) exists
    try { FileUtils.set_contents (dest, "y"); } catch (Error e) {}
    string dest2 = deduplicate_download_path (tmp, base_name);
    GLib.assert_true (dest2.contains ("(2)"));
    // long names must stay within the 255-byte filename limit after " (n)"
    string long_name = "";
    for (int i = 0; i < 250; i++) long_name += "a";
    long_name += ".pdf";
    string long_path = Path.build_filename (tmp, long_name);
    try {
        var stream = File.new_for_path (long_path).create (FileCreateFlags.NONE);
        stream.close ();
    } catch (Error e) {}
    GLib.assert_true (File.new_for_path (long_path).query_exists ());
    string long_dest = deduplicate_download_path (tmp, long_name);
    GLib.assert_true (Path.get_basename (long_dest).length <= 255);
    GLib.assert_true (long_dest != long_path);
    // cleanup
    try { FileUtils.remove (p1); FileUtils.remove (dest); FileUtils.remove (dest2); FileUtils.remove (long_path); FileUtils.remove (long_dest); DirUtils.remove (tmp); } catch (Error e) {}
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/webapp/is_allowed_host", test_is_allowed_host);
    Test.add_func ("/webapp/is_benign_scheme", test_is_benign_scheme);
    Test.add_func ("/webapp/decide_navigation", test_decide_navigation);
    Test.add_func ("/webapp/decide_permission", test_decide_permission);
    Test.add_func ("/webapp/sanitize_profile_name", test_sanitize_profile_name);
    Test.add_func ("/webapp/get_dirs_for_profile", test_get_dirs_for_profile);
    Test.add_func ("/webapp/config_constants", test_config_constants);
    Test.add_func ("/webapp/sanitize_download_filename", test_sanitize_download_filename);
    Test.add_func ("/webapp/deduplicate_download_path", test_deduplicate_download_path);
    return Test.run ();
}
