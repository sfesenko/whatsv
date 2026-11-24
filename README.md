# WebApp

Generic GTK 4 + WebKitGTK 6.0 wrapper that builds a native desktop app for any
website from a small config file. The default config (`misc/whatsapp.conf`)
builds WhatsApp Web (formerly WhatsV); other sites build from their own config.

## Features
- Single instance (D-Bus), multi-window, per-profile isolated sessions
- Persistent `NetworkSession` per profile in
  `XDG_DATA_HOME/<app_id>/profiles/<name>` and the matching cache path under
  `XDG_CACHE_HOME`
- Hardened WebKit: Chrome-like UA, developer extras disabled, notifications
  and WebRTC permissions only on configured hosts
- Hotkeys (no `Super`, PaperWM/GNOME safe): `Ctrl+Q` quit, `Ctrl+W` close,
  `F1`/`Ctrl+?` help, `Ctrl+R`/`F5` reload, `Ctrl+Shift+R` bypass-cache reload,
  `Ctrl+Plus`/`Ctrl+Minus`/`Ctrl+0` zoom, `Alt+Left`/`Ctrl+[` back,
  `Alt+Right`/`Ctrl+]` forward
- Desktop entry, D-Bus service, GSchema, icons, AppStream metadata and the
  `<app_id>` gettext domain generated from the site config

## Dependencies
`gtk4 >= 4.12`, `webkitgtk-6.0 >= 2.42`, `meson >= 1.0`, `vala >= 0.56`,
`glib2`.

## Site configuration
A site config is a flat `key=value` file selected with `-Dsite=<path>`
(relative to the source root). Blank lines and `#` comments are ignored;
invalid keys or values fail at configure time with a message naming the key.

The default config lists only `host=web.whatsapp.com`, so top-level navigation
stays on the start host. Add a `host` entry only for another origin the site
must load in-window (SSO, auth, CDN); each entry also grants privileged
permissions for that host.

| Key | Required | Meaning |
| --- | --- | --- |
| `app_id` | yes | Reverse-DNS ID: at least two dot-separated segments, each starting with an ASCII letter and otherwise using only `A-Z a-z 0-9 _ -`. Drives desktop/D-Bus/schema/icon names, storage root, gettext domain and the default executable (last segment). |
| `app_name` | yes | Name in the window, desktop entry and About dialog. |
| `start_url` | yes | Initial URL. |
| `host` | yes, repeatable | Host and subdomains allowed for in-window navigation and privileged permissions. A leading dot is ignored; `start_url`'s host must be covered. |
| `icon` | yes | Full-color SVG path, relative to the source root or absolute. Must exist. |
| `icon_symbolic` | yes | Symbolic SVG path, relative to the source root or absolute. Must exist. |
| `exec_name` | no | Installed executable; defaults to the last `app_id` segment. Set distinct values to avoid `/usr/bin` collisions. Allowed: `A-Z a-z 0-9 _ -`. |
| `data_dir` | no | Absolute root for profile data instead of `XDG_DATA_HOME`; uses `<data_dir>/<app_id>/profiles/<name>`. Relative values are used verbatim. |
| `cache_dir` | no | Absolute root for profile caches instead of `XDG_CACHE_HOME`; uses `<cache_dir>/<app_id>/profiles/<name>`. Relative values are used verbatim. |
| `ephemeral` | no | `true` uses an ephemeral session and writes no profile data or credentials to disk. Default `false`. |
| `persist_cookies` | no | `true` stores cookies in `<data dir>/cookies.sqlite`; `false` keeps them in memory. Default `true`. |

Example:

```ini
app_id=com.example.myapp
app_name=My App
start_url=https://example.com/
host=example.com
# Paths must exist; these placeholders make `meson setup` fail.
icon=icons/example.svg
icon_symbolic=icons/example-symbolic.svg
```

## Build
Default (WhatsApp):

```sh
meson setup build
meson compile -C build
meson test -C build
meson install -C build --destdir "$PWD/pkgdir"
```

External config:

```sh
meson setup build-mysite -Dsite="$HOME/.config/webapp/mysite.conf"
meson compile -C build-mysite
```

Run (`whatsv` is the last `app_id` segment unless `exec_name` is set):

```sh
./build/src/whatsv
./build/src/whatsv --profile work   # isolated session
./build/src/whatsv --help
```

Sessions live in `<data_dir or XDG_DATA_HOME>/<app_id>/profiles/<name>` and
the matching cache path; `--profile` names are sanitized and limited to 64
characters.

## Encryption
At-rest encryption is the operating system's responsibility. WebApp does not
encrypt profile data or credentials itself; use full-disk encryption (for
example LUKS) or an encrypted home directory. `ephemeral=true` writes no
session data to disk.

## Packaging
- `misc/PKGBUILD` builds `webapp-git` from the local checkout with the bundled
  WhatsApp sample; run `makepkg -s` in `misc/`. Override
  `WEBAPP_SITE=/path/to/site.conf` or `WEBAPP_SRC=/path/to/checkout` for
  another build.
- For a published package, copy it and update `pkgname`/`pkgdesc`/`provides`.
  Installed files derive from `app_id`, so packages install side by side; set
  distinct `exec_name` values when two `app_id`s share a last segment.
