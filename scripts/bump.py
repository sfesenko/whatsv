#!/usr/bin/env python3
"""Bump project version in meson.build and metainfo.xml.in
Usage:
  ./scripts/bump.py                  # show current (meson + PKGBUILD pkgver)
  ./scripts/bump.py --patch          # 0.1.0 -> 0.1.1
  ./scripts/bump.py --minor          # 0.1.0 -> 0.2.0
  ./scripts/bump.py --major          # 0.1.0 -> 1.0.0
  ./scripts/bump.py --version 1.2.3  # explicit
  ./scripts/bump.py --patch --tag    # bump + git commit + tag
"""
import argparse, re, sys, datetime, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
MESON = ROOT / "meson.build"
METAINFO = ROOT / "data/com.github.sfesenko.whatsv.metainfo.xml.in"

def parse_version(v: str):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", v.strip())
    if not m:
        sys.exit(f"invalid version '{v}' expected X.Y.Z")
    return tuple(map(int, m.groups()))

def pkgver_from_git():
    # Mirrors misc/PKGBUILD pkgver()
    try:
        out = subprocess.check_output(["git", "describe", "--long", "--tags"], stderr=subprocess.DEVNULL, text=True).strip()
        # v0.1.0-5-gabc123 -> 0.1.0.r5.gabc123
        out = re.sub(r"^v", "", out)
        out = re.sub(r"([^-]*-g)", r"r\1", out)
        out = out.replace("-", ".")
        return out
    except Exception:
        try:
            out = subprocess.check_output(["git", "log", "-1", "--format=%cs"], text=True).strip()
            return out.replace("-", ".")
        except Exception:
            return "unknown"

def bump_version(cur: str, args):
    if args.version:
        return args.version.strip().lstrip("v")
    major, minor, patch = parse_version(cur)
    if args.major:
        return f"{major+1}.0.0"
    if args.minor:
        return f"{major}.{minor+1}.0"
    if args.patch:
        return f"{major}.{minor}.{patch+1}"
    # no bump flag -> show current, no change
    return cur

def update_meson(old: str, new: str):
    txt = MESON.read_text()
    # Only replace the project version, not meson_version
    # project('whatsv', ..., version: '0.1.0',
    if f"version: '{old}'" not in txt:
        sys.exit(f"cannot find version: '{old}' in meson.build")
    txt = txt.replace(f"version: '{old}'", f"version: '{new}'", 1)
    MESON.write_text(txt)
    print(f"meson.build: {old} -> {new}")

def update_metainfo(old: str, new: str):
    if not METAINFO.exists():
        return
    txt = METAINFO.read_text()
    date = datetime.date.today().isoformat()
    if f'version="{new}"' in txt:
        print(f"metainfo already has {new}, skipping")
        return
    # Insert new <release> right after <releases>
    new_release = f'    <release version="{new}" date="{date}">\n      <description>\n        <p>Release {new}</p>\n      </description>\n    </release>'
    # Find <releases>
    m = re.search(r"<releases>\s*\n", txt)
    if m:
        pos = m.end()
        txt = txt[:pos] + new_release + "\n" + txt[pos:]
    else:
        # Fallback: before first <release>
        txt = re.sub(r"(\s*<release\s+version=\")", new_release + r"\n\1", txt, count=1)
    METAINFO.write_text(txt)
    print(f"metainfo: added <release {new} {date}>")

def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--major", action="store_true")
    g.add_argument("--minor", action="store_true")
    g.add_argument("--patch", action="store_true")
    g.add_argument("--version", type=str)
    ap.add_argument("--tag", action="store_true", help="git commit + tag vX.Y.Z")
    ap.add_argument("--push", action="store_true", help="also git push --tags (implies --tag)")
    args = ap.parse_args()
    if args.push:
        args.tag = True
    mtxt = MESON.read_text()
    # Find project version specifically: project('whatsv', ... version: 'X.Y.Z'
    m = re.search(r"project\s*\(\s*'whatsv'.*?version\s*:\s*'([^']+)'", mtxt, re.DOTALL)
    if not m:
        sys.exit("cannot parse version from meson.build")
    cur = m.group(1)
    new = bump_version(cur, args)
    # No bump flags -> just show current versions (meson + PKGBUILD)
    if new == cur and not args.version:
        # Check if any bump flag was given
        if not (args.major or args.minor or args.patch):
            print(f"meson.build: {cur}")
            print(f"PKGBUILD pkgver: {pkgver_from_git()}")
            return
        print(f"already at {new}")
        return
    parse_version(new)
    update_meson(cur, new)
    update_metainfo(cur, new)
    print(f"bumped {cur} -> {new}")
    print(f"next: git add meson.build data/com.github.sfesenko.whatsv.metainfo.xml.in && git commit -m \"release: v{new}\" && git tag v{new}")
    if args.tag:
        subprocess.run(["git", "add", str(MESON), str(METAINFO)], check=True)
        subprocess.run(["git", "commit", "-m", f"release: v{new}"], check=True)
        subprocess.run(["git", "tag", f"v{new}"], check=True)
        print(f"tagged v{new}")
        if args.push:
            subprocess.run(["git", "push", "origin", "HEAD", "--tags"], check=True)
            print("pushed")

if __name__ == "__main__":
    main()
