using Whatsv.Utils;

void test_is_main_whatsapp_uri () {
    // exact main host
    assert (is_main_whatsapp_uri ("https://web.whatsapp.com/"));
    assert (is_main_whatsapp_uri ("https://web.whatsapp.com"));
    assert (is_main_whatsapp_uri ("https://WEB.WHATSAPP.COM/"));
    // not main
    assert (!is_main_whatsapp_uri ("https://whatsapp.com/"));
    assert (!is_main_whatsapp_uri ("https://www.whatsapp.com/"));
    assert (!is_main_whatsapp_uri ("https://flows.whatsapp.net/flows/cache_management/"));
    assert (!is_main_whatsapp_uri ("https://example.com/"));
    // evil suffix must not be considered main
    assert (!is_main_whatsapp_uri ("https://web.whatsapp.com.evil.com/"));
    assert (!is_main_whatsapp_uri ("https://evil.com/?x=web.whatsapp.com"));
}

void test_is_whatsapp_uri () {
    assert (is_whatsapp_uri ("https://web.whatsapp.com/"));
    assert (is_whatsapp_uri ("https://whatsapp.com/"));
    assert (is_whatsapp_uri ("https://faq.whatsapp.com/"));
    assert (is_whatsapp_uri ("https://flows.whatsapp.net/flows/cache_management/"));
    assert (is_whatsapp_uri ("https://static.whatsapp.net/"));
    assert (is_whatsapp_uri ("https://pps.whatsapp.net/"));
    assert (is_whatsapp_uri ("https://mmg.whatsapp.net/"));
    assert (is_whatsapp_uri ("https://scontent.fbcdn.net/v/abc.jpg"));
    assert (is_whatsapp_uri ("https://www.facebook.com/"));
    // not whatsapp
    assert (!is_whatsapp_uri ("https://example.com/"));
    assert (!is_whatsapp_uri ("https://evil.com/?x=whatsapp.com"));
    assert (!is_whatsapp_uri ("https://web.whatsapp.com.evil.com/"));
    assert (!is_whatsapp_uri ("https://facebook.com.evil.com/"));
    // fallback substring in catch is not used for valid URIs, but ensure evil with whatsapp in query is not misclassified as whatsapp when host is evil.com
    // For valid URI parsing, host is evil.com, so should be false even if query contains whatsapp.com
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
    assert (sanitize_profile_name ("../etc") == "___etc" || sanitize_profile_name ("../etc") == "__etc" || sanitize_profile_name ("../etc").has_prefix ("_"));
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
    get_dirs_for_profile ("work", out data, out cache);
    assert (data.contains ("/com.github.sfesenko.whatsv/profiles/work"));
    assert (cache.contains ("/com.github.sfesenko.whatsv/profiles/work"));
    // traversal sanitized
    get_dirs_for_profile ("../etc/passwd", out data, out cache);
    assert (!data.contains ("../"));
    assert (!data.has_suffix ("/etc/passwd"));
    assert (!cache.contains ("../"));
    // default goes to per-profile isolated (not webkitgtk after revert, but we test that it is under profiles/default)
    // After revert, default is per-profile isolated
    get_dirs_for_profile ("default", out data, out cache);
    assert (data.contains ("/com.github.sfesenko.whatsv/profiles/default"));
    // empty
    get_dirs_for_profile ("", out data, out cache);
    assert (data.contains ("/default"));
}

void test_sanitize_download_filename () {
    assert (sanitize_download_filename ("foo.pdf") == "foo.pdf");
    assert (sanitize_download_filename ("a/b/c.pdf") == "c.pdf");
    assert (sanitize_download_filename ("../.bashrc") == ".bashrc" || sanitize_download_filename ("../.bashrc") == "_bashrc" || sanitize_download_filename ("../.bashrc") == "bashrc");
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
    string tmp = Environment.get_tmp_dir () + "/whatsv-test-%d".printf (Random.int_range (0, 1000000));
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
    Test.add_func ("/whatsv/is_main_whatsapp_uri", test_is_main_whatsapp_uri);
    Test.add_func ("/whatsv/is_whatsapp_uri", test_is_whatsapp_uri);
    Test.add_func ("/whatsv/sanitize_profile_name", test_sanitize_profile_name);
    Test.add_func ("/whatsv/get_dirs_for_profile", test_get_dirs_for_profile);
    Test.add_func ("/whatsv/sanitize_download_filename", test_sanitize_download_filename);
    Test.add_func ("/whatsv/deduplicate_download_path", test_deduplicate_download_path);
    return Test.run ();
}
