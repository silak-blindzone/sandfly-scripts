"""Builds the scripts in src/ into the files SandFly installs, at the top of the repository.

A script with only main.lua becomes <id>.lua. A script with more files, such as translations in
locales/, becomes <id>.zip. The zip files get fixed dates, so a script that didn't change builds
to the same bytes and git sees no change.

Usage: python tools/build.py [id ...]   (all scripts when no id is given)
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
FIXED_DATE = (2026, 1, 1, 0, 0, 0)


def script_id(folder):
    """The id in the manifest, which must match the folder name."""
    with open(os.path.join(folder, 'main.lua'), encoding='utf-8') as f:
        match = re.search(r"\bid\s*=\s*'([^']+)'", f.read())
    if match is None:
        sys.exit(f'{folder}: no id in the manifest')
    return match.group(1)


def files_of(folder):
    found = []
    for base, dirs, names in os.walk(folder):
        dirs.sort()
        for name in sorted(names):
            path = os.path.join(base, name)
            found.append((path, os.path.relpath(path, folder).replace(os.sep, '/')))
    return found


def build(name):
    folder = os.path.join(SRC, name)
    sid = script_id(folder)
    if sid != name:
        sys.exit(f'{name}: the folder must be named after the id, {sid}')
    files = files_of(folder)
    lua_out = os.path.join(ROOT, sid + '.lua')
    zip_out = os.path.join(ROOT, sid + '.zip')
    if [arc for _, arc in files] == ['main.lua']:
        with open(files[0][0], 'rb') as f:
            data = f.read()
        with open(lua_out, 'wb') as f:
            f.write(data)
        out = lua_out
    else:
        with zipfile.ZipFile(zip_out, 'w', zipfile.ZIP_DEFLATED) as z:
            for path, arc in files:
                info = zipfile.ZipInfo(arc, FIXED_DATE)
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(path, 'rb') as f:
                    z.writestr(info, f.read())
        out = zip_out
    print(os.path.relpath(out, ROOT))


def main():
    names = sys.argv[1:] or sorted(
        n for n in os.listdir(SRC) if os.path.isfile(os.path.join(SRC, n, 'main.lua')))
    for name in names:
        build(name)


if __name__ == '__main__':
    main()
