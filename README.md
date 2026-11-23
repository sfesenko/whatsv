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
  service, GSchema, icons and AppStream metadata named after `<app_id>`

## Dependencies
- `gtk4 >= 4.12`
- `webkitgtk-6.0 >= 2.42`
- `meson >= 1.0`, `vala >= 0.56`, `glib2`

## Site configuration
A site config is a flat `key=value` file selected at configure time with
`-Dsite=<path>` (relative paths are resolved against the source root).
Blank lines and lines starting with `#` are ignored.

| Key | Required | Meaning |
| --- | --- | --- |
| `app_id` | yes | Reverse-DNS application ID. Drives the desktop file, D-Bus service, GSchema, icon names, storage directory and the installed executable name (its last segment). |
| `app_name` | yes | Human-readable name shown in the window, desktop entry and About dialog. |
| `start_url` | yes | URL loaded when the app starts. |
| `host` | yes, repeatable | Host allowed for navigation and privileged permissions. Repeat the key once per host; a leading dot matches subdomains (`.example.com`). At least one is required. |
| `icon` | no | Path to a full-color SVG icon, relative to the source root or absolute. |
| `icon_symbolic` | no | Path to a symbolic SVG icon, relative to the source root or absolute. |
| `data_dir` | no | Root directory for persistent profile data instead of `XDG_DATA_HOME`. `<data_dir>/<app_id>/profiles/<name>` is used. |
| `cache_dir` | no | Root directory for profile caches instead of `XDG_CACHE_HOME`. `<cache_dir>/<app_id>/profiles/<name>` is used. |
| `ephemeral` | no | `true` uses an ephemeral WebKit session: no profile data or credentials are written to disk. Defaults to `false`. |

Example:

```ini
app_id=com.example.myapp
app_name=My App
start_url=https://example.com/
host=example.com
host=.example.com
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

Run (executable name is the last segment of `app_id`):

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
  executable names derive from `app_id`, so packages install side by side.
