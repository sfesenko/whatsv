# WebApp

Generic GTK 4 + WebKitGTK 6.0 web app wrapper. One source tree builds a
native-feeling desktop app for any website from a small config file.

The default config (`sites/whatsapp.conf`) builds the familiar WhatsApp Web
client — previously shipped as WhatsV — with persistent sessions and profiles.
`sites/other.conf` shows the same source tree building a second app.

## Features
- Single-instance (D-Bus activated) with multi-window, per-profile isolated sessions
- Persistent `NetworkSession` per profile under
  `XDG_DATA_HOME/<app_id>/profiles/<name>` + `XDG_CACHE_HOME/<app_id>/profiles/<name>`
- Hardened WebKit: Chrome-like UA, disabled `enable_developer_extras`,
  notifications + WebRTC permissions only for the configured hosts
- Native hotkeys (no `Super`, PaperWM/GNOME safe):
  - `Ctrl+Q` quit, `Ctrl+W` close window, `F1`/`Ctrl+?` help
  - `Ctrl+R` / `F5` reload, `Ctrl+Shift+R` reload bypass cache
  - `Ctrl+Plus/Equal` / `Ctrl+Minus` / `Ctrl+0` zoom in/out/reset
  - `Alt+Left` / `Ctrl+[` back, `Alt+Right` / `Ctrl+]` forward
- Desktop integration generated from the site config: desktop entry, D-Bus
  service, GSchema, icons, AppStream metadata and the gettext domain named
  after `<app_id>`

## Dependencies
- `gtk4 >= 4.12`
- `webkitgtk-6.0 >= 2.42`
- `meson >= 1.0`, `vala >= 0.56`, `glib2`

## Site configuration
A site config is a flat `key=value` file selected at configure time with
`-Dsite=<path>` (relative paths are resolved against the source root).
Blank lines and lines starting with `#` are ignored.

`app_id`, `app_name`, `start_url`, at least one `host`, `icon` and
`icon_symbolic` are required; the icon files must exist, otherwise
`meson setup` fails. `app_id` must be reverse-DNS: at least two dot-separated
segments, each starting with an ASCII letter and otherwise using only
`A-Z a-z 0-9 _ -`. Invalid IDs, unknown keys and malformed booleans fail at
configure time with a message naming the key.

The default WhatsApp config deliberately ships only `host=web.whatsapp.com`,
which narrows top-level navigation to the start host.

| Key | Required | Meaning |
| --- | --- | --- |
| `app_id` | yes | Reverse-DNS application ID. Drives the desktop file, D-Bus service, GSchema, icon names, storage directory, gettext domain and the default installed executable name (its last segment). |
| `app_name` | yes | Human-readable name shown in the window, desktop entry and About dialog. |
| `start_url` | yes | URL loaded when the app starts. |
| `host` | yes, repeatable | Host allowed for navigation and privileged permissions. Repeat the key once per host. An entry matches the host itself and every subdomain; a leading dot is stripped, so `example.com` and `.example.com` are equivalent. At least one is required, and the `start_url` host must be covered by one of the entries. |
| `icon` | yes | Path to a full-color SVG icon, relative to the source root or absolute. Must exist at configure time. |
| `icon_symbolic` | yes | Path to a symbolic SVG icon, relative to the source root or absolute. Must exist at configure time. |
| `exec_name` | no | Installed executable name. Defaults to the last segment of `app_id`. Set it when two sites share a last segment but the packages should not install the same file in `/usr/bin`. Allowed characters: `A-Z a-z 0-9 _ -`. |
| `data_dir` | no | Absolute path to a root directory for persistent profile data instead of `XDG_DATA_HOME`. `<data_dir>/<app_id>/profiles/<name>` is used. Relative values are not resolved; they are used verbatim and usually point outside the intended location. |
| `cache_dir` | no | Absolute path to a root directory for profile caches instead of `XDG_CACHE_HOME`. `<cache_dir>/<app_id>/profiles/<name>` is used. Relative values are not resolved; they are used verbatim. |
| `ephemeral` | no | `true` uses an ephemeral WebKit session: no profile data or credentials are written to disk. Defaults to `false`. |
| `persist_cookies` | no | `true` stores cookies in `<data dir>/cookies.sqlite` so site logins survive restarts. `false` keeps cookies in memory for the current run only. Defaults to `true`. |

Example:

```ini
app_id=com.example.myapp
app_name=My App
start_url=https://example.com/
host=example.com
# Replace these with paths to SVG files that exist in your tree (relative to
# the source root) or absolute paths. The values below are placeholders and
# `meson setup` fails while the files are missing.
icon=icons/example.svg
icon_symbolic=icons/example-symbolic.svg
```

## Build
The default build uses `sites/whatsapp.conf`:

```sh
meson setup build
meson compile -C build
meson test -C build
meson install -C build --destdir "$PWD/pkgdir"
```

Build a second app from another bundled config:

```sh
meson setup build-other -Dsite=sites/other.conf
meson compile -C build-other
meson test -C build-other
```

Build from a config kept outside the source tree:

```sh
meson setup build-mysite -Dsite="$HOME/.config/webapp/mysite.conf"
meson compile -C build-mysite
```

Run (executable name is the last segment of `app_id` unless `exec_name` is set):

```sh
./build/src/whatsv
./build/src/whatsv --profile work   # isolated session
./build/src/whatsv --help
./build-other/src/other
```

Profile sessions:
- default: `<data_dir or XDG_DATA_HOME>/<app_id>/profiles/default` and the matching cache path
- custom: `.../profiles/<name>` (sanitized, max 64 chars)

## Encryption
At-rest encryption is the operating system's responsibility, not the app's.
WebApp does not encrypt profile directories or credentials itself; use
full-disk encryption (for example LUKS) or an encrypted home directory if
session data needs to be protected on disk. `ephemeral=true` avoids writing
session data at all.

## Packaging
- AUR `misc/PKGBUILD` (`webapp-git`, default WhatsApp config) — `makepkg -s`
  inside `misc/`
- One source tree, one package per site: copy `misc/PKGBUILD`, change
  `pkgname` and point `-Dsite` at that site's config. Installed files and
  the default executable name derive from `app_id`, so packages normally
  install side by side; if two `app_id`s share a last segment, set distinct
  `exec_name` values (defaults otherwise collide in `/usr/bin`).
