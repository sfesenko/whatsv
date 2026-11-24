using WebApp.Utils;

const string TEST_HOSTS = "example.com,api.example.com";
const string TEST_APP_ID = "com.example.app";

void test_is_allowed_host () {
    // exact and subdomain matches, case-insensitive
    assert (is_allowed_host ("https://example.com/", TEST_HOSTS));
    assert (is_allowed_host ("https://EXAMPLE.COM/", TEST_HOSTS));
    assert (is_allowed_host ("https://example.com/?ref=chat", TEST_HOSTS));
    assert (is_allowed_host ("https://chat.example.com/", TEST_HOSTS));
    assert (is_allowed_host ("https://api.example.com/login", TEST_HOSTS));
    // a leading dot is ignored
    assert (is_allowed_host ("https://chat.example.com/", ".example.com"));
    // hosts not covered by the list are rejected
    assert (!is_allowed_host ("https://faq.example.net/", TEST_HOSTS));
    // lookalikes and query tricks must not match
    assert (!is_allowed_host ("https://example.com.evil.com/", TEST_HOSTS));
    assert (!is_allowed_host ("https://evil.com/?x=example.com", TEST_HOSTS));
    assert (!is_allowed_host ("https://notexample.com/", TEST_HOSTS));
    // unparseable URI falls back to the string check and finds no allowed host
    assert (!is_allowed_host ("https://exa%mple.com/", TEST_HOSTS));
}

void test_is_benign_scheme () {
    assert (is_benign_scheme ("about:blank"));
    assert (is_benign_scheme ("data:text/plain,hi"));
    assert (is_benign_scheme ("blob:https://example.com/x"));
    assert (is_benign_scheme ("webkit:something"));
    assert (!is_benign_scheme ("https://example.com/"));
    assert (!is_benign_scheme ("ftp://example.com/"));
    assert (!is_benign_scheme ("not a uri"));
}

void test_decide_navigation () {
    // same-origin SPA routes stay in the view, clicked or not
    assert (decide_navigation ("https://example.com/chat", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("https://example.com/chat", TEST_HOSTS, true, false) == NavigationDisposition.IN_VIEW);
    // benign internal schemes stay in the view
    assert (decide_navigation ("about:blank", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("data:text/plain,hi", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("blob:https://example.com/x", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("webkit:something", TEST_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    // external links are handed to the browser when clicked or opened in a new window
    assert (decide_navigation ("https://other.example/", TEST_HOSTS, true, false) == NavigationDisposition.OPEN_EXTERNAL);
    assert (decide_navigation ("https://other.example/", TEST_HOSTS, false, true) == NavigationDisposition.OPEN_EXTERNAL);
    // non-click external navigations and unknown schemes are ignored
    assert (decide_navigation ("https://other.example/", TEST_HOSTS, false, false) == NavigationDisposition.IGNORE);
    assert (decide_navigation ("ftp://example.com/", TEST_HOSTS, false, false) == NavigationDisposition.IGNORE);
}

void test_sanitize_profile_name () {
    assert (sanitize_profile_name ("") == "default");
    assert (sanitize_profile_name ("   ") == "default");
    assert (sanitize_profile_name (".") == "default");
    assert (sanitize_profile_name ("..") == "default");
    assert (sanitize_profile_name ("work") == "work");
    assert (sanitize_profile_name ("my profile") == "my_profile");
    assert (sanitize_profile_name ("a/b\\c") == "a_b_c");
    assert (sanitize_profile_name (".hidden") == "hidden");
    // traversal
    assert (sanitize_profile_name ("../etc") == "_etc");
    // long (>64) should be truncated/hashed, still within limit and matches whitelist
    string long = "";
    for (int i = 0; i < 100; i++) long += "a";
    string s = sanitize_profile_name (long);
    assert (s.length <= 64);
    assert (s.length > 0);
    try {
        var re = new Regex ("^[A-Za-z0-9._-]+$");
        assert (re.match (s));
    } catch (Error e) { assert_not_reached (); }
    // unicode and special
    string u = sanitize_profile_name ("профіль");
    assert (u != "" && u != "." && u != "..");
    try {
        var re2 = new Regex ("^[A-Za-z0-9._-]+$");
        assert (re2.match (u));
    } catch (Error e) { assert_not_reached (); }
}

void test_get_dirs_for_profile () {
    string data, cache;
    get_dirs_for_profile ("work", TEST_APP_ID, "", "", out data, out cache);
    assert (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "work"));
    assert (cache == Path.build_filename (Environment.get_user_cache_dir (), TEST_APP_ID, "profiles", "work"));
    // both roots are sensitive: traversal is sanitized in each
    get_dirs_for_profile ("../etc/passwd", TEST_APP_ID, "", "", out data, out cache);
    assert (!data.contains ("../"));
    assert (!data.has_suffix ("/etc/passwd"));
    assert (!cache.contains ("../"));
    assert (!cache.has_suffix ("/etc/passwd"));
    get_dirs_for_profile ("default", TEST_APP_ID, "", "", out data, out cache);
    assert (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "default"));
    assert (cache == Path.build_filename (Environment.get_user_cache_dir (), TEST_APP_ID, "profiles", "default"));
    // empty profile sanitizes to default
    get_dirs_for_profile ("", TEST_APP_ID, "", "", out data, out cache);
    assert (data == Path.build_filename (Environment.get_user_data_dir (), TEST_APP_ID, "profiles", "default"));
    // explicit roots replace the XDG roots verbatim for both data and cache
    get_dirs_for_profile ("work", TEST_APP_ID, "/tmp/site-data", "/tmp/site-cache", out data, out cache);
    assert (data == Path.build_filename ("/tmp/site-data", TEST_APP_ID, "profiles", "work"));
    assert (cache == Path.build_filename ("/tmp/site-cache", TEST_APP_ID, "profiles", "work"));
}

void test_config_constants () {
    // Generated constants must describe a usable configuration: the start URL
    // is allowed, and profile directories follow the configured app id/roots.
    assert (is_allowed_host (Config.SITE_START_URL, Config.SITE_HOSTS));
    string data, cache;
    get_dirs_for_profile ("work", Config.APP_ID, Config.DATA_DIR_ROOT, Config.CACHE_DIR_ROOT, out data, out cache);
    assert (data.has_prefix (Config.DATA_DIR_ROOT != "" ? Config.DATA_DIR_ROOT : Environment.get_user_data_dir ()));
    assert (cache.has_prefix (Config.CACHE_DIR_ROOT != "" ? Config.CACHE_DIR_ROOT : Environment.get_user_cache_dir ()));
    assert (data.contains ("/" + Config.APP_ID + "/profiles/work"));
    assert (cache.contains ("/" + Config.APP_ID + "/profiles/work"));
}

void test_sanitize_download_filename () {
    assert (sanitize_download_filename ("foo.pdf") == "foo.pdf");
    assert (sanitize_download_filename ("a/b/c.pdf") == "c.pdf");
    assert (sanitize_download_filename ("../.bashrc") == ".bashrc");
    // basename handling
    assert (sanitize_download_filename ("") == "download");
    assert (sanitize_download_filename (".") == "download");
    assert (sanitize_download_filename ("..") == "download");
    // unsafe chars replaced
    string s = sanitize_download_filename ("a/b\\c:d*e?f\"g<h>i|j.pdf");
    try {
        var re = new Regex ("^[A-Za-z0-9._-]+$");
        assert (re.match (s));
    } catch (Error e) { assert_not_reached (); }
    // long
    string long = "";
    for (int i = 0; i < 300; i++) long += "a";
    long += ".pdf";
    string l = sanitize_download_filename (long);
    assert (l.length <= 255);
    assert (l.has_suffix (".pdf") || l.length == 255);
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
    assert (dest != p1);
    assert (dest.contains ("(1)"));
    // second dedup should give (2) if (1) exists
    try { FileUtils.set_contents (dest, "y"); } catch (Error e) {}
    string dest2 = deduplicate_download_path (tmp, base_name);
    assert (dest2.contains ("(2)"));
    // cleanup
    try { FileUtils.remove (p1); FileUtils.remove (dest); FileUtils.remove (dest2); DirUtils.remove (tmp); } catch (Error e) {}
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/webapp/is_allowed_host", test_is_allowed_host);
    Test.add_func ("/webapp/is_benign_scheme", test_is_benign_scheme);
    Test.add_func ("/webapp/decide_navigation", test_decide_navigation);
    Test.add_func ("/webapp/sanitize_profile_name", test_sanitize_profile_name);
    Test.add_func ("/webapp/get_dirs_for_profile", test_get_dirs_for_profile);
    Test.add_func ("/webapp/config_constants", test_config_constants);
    Test.add_func ("/webapp/sanitize_download_filename", test_sanitize_download_filename);
    Test.add_func ("/webapp/deduplicate_download_path", test_deduplicate_download_path);
    return Test.run ();
}
