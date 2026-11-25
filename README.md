# WebApp

GTK 4 + WebKitGTK 6.0 website wrapper.

- Default config: `misc/whatsapp.conf` (WhatsApp Web, formerly WhatsV)
- Other sites: separate site config with `-Dsite=<path>`

## Features

- Single instance (D-Bus), multi-window, per-profile sessions
- Sessions: `XDG_DATA_HOME/<app_id>/profiles/<name>`, cache under `XDG_CACHE_HOME`
- WebKit: Chrome-like UA, developer extras disabled
- Permissions: notifications/media-key/device-info only on configured hosts
- Camera, microphone and screen sharing: prompt
- Cross-site cookies: both domains must be configured
- Hotkeys: `Ctrl+Q` quit, `Ctrl+W` close, `F1`/`Ctrl+?` help,
  `Ctrl+R`/`F5` reload, `Ctrl+Shift+R` bypass-cache reload,
  `Ctrl+Plus`/`Ctrl+Minus`/`Ctrl+0` zoom,
  `Alt+Left`/`Ctrl+[` back, `Alt+Right`/`Ctrl+]` forward
- Generated files: desktop entry, D-Bus service, GSchema, icons, AppStream,
  `<app_id>` gettext domain

## Dependencies

`gtk4 >= 4.12`, `webkitgtk-6.0 >= 2.42`, `meson >= 1.0`, `vala >= 0.56`, `glib2`.

## Site configuration

- `-Dsite=<path>`: relative to source root
- Blank lines and `#` comments ignored
- Invalid keys or values: configure-time error naming the key
- `host` repeatable; default config: `host=web.whatsapp.com`
- Add `host` entries for in-window origins (SSO, auth, CDN)
- ITP disabled for messaging single-page apps

Permissions:

- Top-level page must match `host`
- Camera/microphone/screen sharing always prompts
- Cross-site cookie access requires both domains in `host`

| Key | Required | Meaning |
| --- | --- | --- |
| `app_id` | yes | Reverse-DNS ID. Segments: at least two; each starts with ASCII letter; allowed `A-Z a-z 0-9 _ -`. Drives desktop/D-Bus/schema/icon names, storage root, gettext domain, default executable (last segment). |
| `app_name` | yes | Window, desktop entry and About name. XML characters escaped; control characters/backslashes rejected. |
| `start_url` | yes | Initial URL. `http://` or `https://`; host must match a `host` entry. |
| `host` | yes, repeatable | FQDN allowed for in-window navigation and privileged permissions. Leading dot ignored. No wildcards, ports, schemes, paths or comma lists. `localhost` allowed. Single-label public suffixes rejected. IPv4/IPv6 exact; domains also match subdomains. |
| `icon` | yes | Full-color SVG, relative to source root or absolute. Must exist. |
| `icon_symbolic` | yes | Symbolic SVG, relative to source root or absolute. Must exist. |
| `exec_name` | no | Installed executable; default: last `app_id` segment. Allowed `A-Z a-z 0-9 _ -`. Use distinct values to avoid `/usr/bin` collisions. |
| `data_dir` | no | Absolute data root; default `XDG_DATA_HOME`. Path: `<data_dir>/<app_id>/profiles/<name>`. Relative rejected. |
| `cache_dir` | no | Absolute cache root; default `XDG_CACHE_HOME`. Path: `<cache_dir>/<app_id>/profiles/<name>`. Relative rejected. |
| `ephemeral` | no | `true`: ephemeral session, no profile/credential data on disk. Default `false`. |
| `persist_cookies` | no | `true`: cookies in `<data dir>/cookies.sqlite`, persistent credentials enabled. `false`: memory cookies, persistent credentials disabled. Default `true`. |

Example:

```ini
app_id=com.example.myapp
app_name=My App
start_url=https://example.com/
host=example.com
# Placeholders cause `meson setup` to fail.
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

## Run

`whatsv` = last `app_id` segment unless `exec_name` is set.

```sh
./build/src/whatsv
./build/src/whatsv --profile work   # isolated session
./build/src/whatsv --help
```

Build tree:

```sh
glib-compile-schemas ./build/data
GSETTINGS_SCHEMA_DIR=./build/data ./build/src/whatsv
```

Sessions:

- Path: `<data_dir or XDG_DATA_HOME>/<app_id>/profiles/<name>`
- Cache: matching path under `XDG_CACHE_HOME`
- `--profile`: sanitized, max 64 characters
- Replaced characters: short hash suffix; `a/b` and `a_b` stay separate
- Desktop entry not D-Bus-only: `Exec=whatsv --profile work` forwards the profile
- Window size/zoom: per application, not per profile

## Encryption

- At-rest encryption: OS responsibility
- No built-in profile/credential encryption
- Use full-disk encryption (LUKS) or encrypted home
- `ephemeral=true`: no session data on disk

## Packaging

- `misc/PKGBUILD`: builds `webapp-git` from local checkout with bundled WhatsApp sample
- Run: `makepkg -s` in `misc/`
- Override: `WEBAPP_SITE=/path/to/site.conf`, `WEBAPP_SRC=/path/to/checkout`
- Published package: copy PKGBUILD; update `pkgname`/`pkgdesc`/`provides`
- Installed files derive from `app_id`; packages install side by side
- Distinct `exec_name` required when two `app_id`s share a last segment
