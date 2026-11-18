"""Checks a script package: Lua syntax, manifest rules, and that every translatable string has a
Slovak entry."""
import json
import re
import sys

import luaparser.ast as ast

pkg = sys.argv[1]
src = open(pkg + '/main.lua', encoding='utf-8').read()
ast.parse(src)

# luaparser accepts a line break inside a quoted string, which real Lua rejects.
for n, line in enumerate(src.split('\n'), 1):
    code = line.split('--')[0]
    stripped = re.sub(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"", '', code)
    if "'" in stripped or '"' in stripped:
        print('UNCLOSED STRING on line', n, ':', line.strip())

manifest_part = src.split('\nlocal tr')[0]

# An onDemand script can't have apps, rules, navigation or button settings, and its commands
# have only id and title.
if re.search(r"onDemand\s*=\s*true", manifest_part):
    for bad in [r"\bapps\s*=", r"\brules\s*=", r"\bnavigation\s*=", r"type\s*=\s*'button'",
                r"\bgesture\s*=", r"\bkeys\s*=", r"\bmenu\s*=", r"\bcontrol\s*="]:
        if re.search(bad, manifest_part):
            print('ONDEMAND NOT ALLOWED:', bad)
print('lua ok')

try:
    loc = json.load(open(pkg + '/locales/sk.json', encoding='utf-8'))
except FileNotFoundError:
    print('no locales')
    sys.exit(0)

STR = r"'((?:[^'\\]|\\.)*)'"
used = set(re.findall(r"\btr\(" + STR, src))
manifest = set(re.findall(r"\b(?:name|title|summary|label|description) = " + STR, manifest_part))
wanted = {s.replace("\\'", "'") for s in used | manifest}
missing = [s for s in sorted(wanted) if s not in loc]
unused = [k for k in loc if k not in wanted]
for s in missing:
    print('MISSING:', s)
for s in unused:
    print('UNUSED:', s)
print('translations ok' if not missing else 'translations incomplete')
