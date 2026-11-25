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
METAINFO = ROOT / "data/app.metainfo.xml.in"
PO = ROOT / "po/en.po"

def parse_version(v: str):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", v.strip())
    if not m:
        sys.exit(f"invalid version '{v}' expected X.Y.Z")
    return tuple(map(int, m.groups()))

def pkgver_from_git():
    # Mirrors misc/PKGBUILD pkgver(): the last commit date with dots.
    try:
        out = subprocess.check_output(
            ["git", "-C", str(ROOT), "log", "-1", "--format=%cs"],
            stderr=subprocess.DEVNULL, text=True).strip()
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
    # project('webapp', ..., version: '0.1.0',
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

def update_po(old: str, new: str):
    if not PO.exists():
        return
    txt = PO.read_text()
    needle = f"Project-Id-Version: WebApp {old}\\n"
    if needle not in txt:
        return
    PO.write_text(txt.replace(needle, f"Project-Id-Version: WebApp {new}\\n"))
    print(f"po/en.po: Project-Id-Version {old} -> {new}")

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
    # Find project version specifically: project('webapp', ... version: 'X.Y.Z'
    m = re.search(r"project\s*\(\s*'webapp'.*?version\s*:\s*'([^']+)'", mtxt, re.DOTALL)
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
    update_po(cur, new)
    print(f"bumped {cur} -> {new}")
    print(f"next: git add meson.build data/app.metainfo.xml.in po/en.po && git commit -m \"release: v{new}\" && git tag v{new}")
    if args.tag:
        paths = [str(MESON), str(METAINFO)]
        if PO.exists():
            paths.append(str(PO))
        # --only keeps unrelated staged changes out of the release commit.
        subprocess.run(["git", "commit", "--only", "-m", f"release: v{new}", "--", *paths], check=True)
        subprocess.run(["git", "tag", f"v{new}"], check=True)
        print(f"tagged v{new}")
        if args.push:
            # Push branch (triggers CI) and the new tag (triggers Release) separately.
            # Using --follow-tags would also work, but explicit is clearer and avoids pushing all tags.
            subprocess.run(["git", "push", "origin", "HEAD"], check=True)
            subprocess.run(["git", "push", "origin", f"v{new}"], check=True)
            print("pushed branch and tag v{new} (CI on master, Release on tag)".format(new=new))

if __name__ == "__main__":
    main()
