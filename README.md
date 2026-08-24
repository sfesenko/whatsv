# WhatsV
Simple GTK WhatsApp Web Client, inspired by [WhatsTux](https://gitlab.com/nexxontech/whatstux)

GTK 4 + WebKitGTK 6.0 wrapper for https://web.whatsapp.com with persistent sessions and profiles.

## Features
- Single-instance (D-Bus activated) with multi-window, per-profile isolated sessions
- Persistent `NetworkSession` per profile: `XDG_DATA_HOME/com.github.sfesenko.whatsv/profiles/<name>` + `XDG_CACHE_HOME/...`
- Legacy `~/.local/share/whatsv` detected with migration hint
- Hardened WebKit: Chrome-like UA, disabled `enable_developer_extras`, notifications + WebRTC permissions for calls
- Native hotkeys (no `Super`, PaperWM/GNOME safe):
  - `Ctrl+Q` quit, `Ctrl+W` close window, `F1`/`Ctrl+?` help
  - `Ctrl+R` / `F5` reload, `Ctrl+Shift+R` reload bypass cache
  - `Ctrl+Plus/Equal` / `Ctrl+Minus` / `Ctrl+0` zoom in/out/reset
  - `Alt+Left` / `Ctrl+[` back, `Alt+Right` / `Ctrl+]` forward
- Desktop integration: `com.github.sfesenko.whatsv` icons, GSchema (`window-width` etc.), AppStream validates

## Dependencies
- `gtk4 >= 4.12`
- `webkitgtk-6.0 >= 2.42`
- `meson >= 1.0`, `vala >= 0.56`, `glib2`

## Build
```sh
meson setup build --prefix /usr
meson compile -C build
meson install -C build --destdir /  # or --destdir pkgdir for packaging
```

Run:
```sh
./build/src/whatsv
./build/src/whatsv --profile work   # isolated session
./build/src/whatsv --help
```

Profile sessions:
- default: `~/.local/share/com.github.sfesenko.whatsv/profiles/default` + `~/.cache/...`
- custom: `.../profiles/<name>` (sanitized, max 64 chars)

## Packaging
- AUR `misc/PKGBUILD` (`whatsv-git`) — `makepkg -s` inside `misc/`
