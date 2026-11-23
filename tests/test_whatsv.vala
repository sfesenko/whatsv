using WebApp.Utils;

const string WA_HOSTS = "web.whatsapp.com";
const string OTHER_HOSTS = "other.ai,.other.ai,auth.other.ai";

void test_is_allowed_host () {
    // exact and subdomain matches, case-insensitive
    assert (is_allowed_host ("https://web.whatsapp.com/", WA_HOSTS));
    assert (is_allowed_host ("https://WEB.WHATSAPP.COM/", WA_HOSTS));
    assert (is_allowed_host ("https://web.whatsapp.com/?ref=chat", WA_HOSTS));
    assert (is_allowed_host ("https://other.ai/chat/agent", OTHER_HOSTS));
    assert (is_allowed_host ("https://auth.other.ai/login", OTHER_HOSTS));
    // the shipped WhatsApp config deliberately allows only the start host
    assert (!is_allowed_host ("https://faq.whatsapp.com/", WA_HOSTS));
    // lookalikes and query tricks must not match
    assert (!is_allowed_host ("https://web.whatsapp.com.evil.com/", WA_HOSTS));
    assert (!is_allowed_host ("https://other.ai.evil.com/", OTHER_HOSTS));
    assert (!is_allowed_host ("https://evil.com/?x=whatsapp.com", WA_HOSTS));
    assert (!is_allowed_host ("https://notother.ai/", OTHER_HOSTS));
    // unparseable URI falls back to the string check and finds no allowed host
    assert (!is_allowed_host ("https://exa%mple.com/", WA_HOSTS));
}

void test_is_benign_scheme () {
    assert (is_benign_scheme ("about:blank"));
    assert (is_benign_scheme ("data:text/plain,hi"));
    assert (is_benign_scheme ("blob:https://other.ai/x"));
    assert (is_benign_scheme ("webkit:something"));
    assert (!is_benign_scheme ("https://other.ai/"));
    assert (!is_benign_scheme ("ftp://other.ai/"));
    assert (!is_benign_scheme ("not a uri"));
}

void test_decide_navigation () {
    // same-origin SPA routes stay in the view, clicked or not
    assert (decide_navigation ("https://other.ai/chat/agent", OTHER_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("https://other.ai/chat/agent", OTHER_HOSTS, true, false) == NavigationDisposition.IN_VIEW);
    // benign internal schemes stay in the view
    assert (decide_navigation ("about:blank", OTHER_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("data:text/plain,hi", OTHER_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("blob:https://other.ai/x", OTHER_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    assert (decide_navigation ("webkit:something", OTHER_HOSTS, false, false) == NavigationDisposition.IN_VIEW);
    // external links are handed to the browser when clicked or opened in a new window
    assert (decide_navigation ("https://example.com/", OTHER_HOSTS, true, false) == NavigationDisposition.OPEN_EXTERNAL);
    assert (decide_navigation ("https://example.com/", OTHER_HOSTS, false, true) == NavigationDisposition.OPEN_EXTERNAL);
    // non-click external navigations and unknown schemes are ignored
    assert (decide_navigation ("https://example.com/", OTHER_HOSTS, false, false) == NavigationDisposition.IGNORE);
    assert (decide_navigation ("ftp://other.ai/", OTHER_HOSTS, false, false) == NavigationDisposition.IGNORE);
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
    get_dirs_for_profile ("work", "com.github.sfesenko.whatsv", "", "", out data, out cache);
    assert (data.contains ("/com.github.sfesenko.whatsv/profiles/work"));
    assert (cache.contains ("/com.github.sfesenko.whatsv/profiles/work"));
    // both roots are sensitive: traversal is sanitized in each
    get_dirs_for_profile ("../etc/passwd", "com.github.sfesenko.whatsv", "", "", out data, out cache);
    assert (!data.contains ("../"));
    assert (!data.has_suffix ("/etc/passwd"));
    assert (!cache.contains ("../"));
    assert (!cache.has_suffix ("/etc/passwd"));
    get_dirs_for_profile ("default", "com.github.sfesenko.whatsv", "", "", out data, out cache);
    assert (data.contains ("/com.github.sfesenko.whatsv/profiles/default"));
    assert (cache.contains ("/com.github.sfesenko.whatsv/profiles/default"));
    // empty profile sanitizes to default
    get_dirs_for_profile ("", "com.github.sfesenko.whatsv", "", "", out data, out cache);
    assert (data.contains ("/default"));
    // explicit roots replace the XDG roots verbatim for both data and cache
    get_dirs_for_profile ("work", "com.github.sfesenko.whatsv", "/tmp/site-data", "/tmp/site-cache", out data, out cache);
    assert (data.has_prefix ("/tmp/site-data/"));
    assert (cache.has_prefix ("/tmp/site-cache/"));
    assert (data.contains ("/com.github.sfesenko.whatsv/profiles/work"));
    assert (cache.contains ("/com.github.sfesenko.whatsv/profiles/work"));
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
    Test.add_func ("/whatsv/is_allowed_host", test_is_allowed_host);
    Test.add_func ("/whatsv/is_benign_scheme", test_is_benign_scheme);
    Test.add_func ("/whatsv/decide_navigation", test_decide_navigation);
    Test.add_func ("/whatsv/sanitize_profile_name", test_sanitize_profile_name);
    Test.add_func ("/whatsv/get_dirs_for_profile", test_get_dirs_for_profile);
    Test.add_func ("/whatsv/sanitize_download_filename", test_sanitize_download_filename);
    Test.add_func ("/whatsv/deduplicate_download_path", test_deduplicate_download_path);
    return Test.run ();
}
