"""Cross-check that every L10n key referenced from Swift code actually exists.

Reference styles used in the app:
  * `t(.someKey)` inside views
  * `s(.someKey)` inside AppModel (non-view code)
  * `L10n.string(.someKey, language)` inside controllers
  * `return .someKey` inside the `localizationKey` computed properties of the
    HUD enums (Alignment / Layout / Metric)
All of them are collected here and compared with the `case` list of `L10n.Key`.
Missing a style means a typo can reach a release, so the patterns are listed
explicitly rather than inferred.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IOS = REPO / "ios-app"

l10n_source = (IOS / "L10n.swift").read_text(encoding="utf-8")

# Keys declared in the enum.
defined = set(re.findall(r"^        case (\w+)\s*$", l10n_source, re.M))
if not defined:
    raise SystemExit("could not parse L10n.Key cases")

PATTERNS = [
    r"\bt\(\.(\w+)\)",             # t(.key)          views
    r"\bs\(\.(\w+)\)",             # s(.key)          AppModel
    r"\bstring\(\.(\w+),",         # L10n.string(.key, language)
    r"^            return \.(\w+)$",   # localizationKey switch, single-line
    r"case \.\w+: return \.(\w+)",     # localizationKey switch, inline
    r"\? \.(\w+) : \.(\w+)",           # t(flag ? .a : .b) - two groups
]

used: dict[str, set[str]] = {}

for path in sorted(IOS.glob("*.swift")):
    text = path.read_text(encoding="utf-8")

    found: set[str] = set()
    for pattern in PATTERNS:
        # A pattern may capture several alternatives (the ternary); flatten them.
        for groups in re.findall(pattern, text, re.M):
            if isinstance(groups, str):
                found.add(groups)
            else:
                found.update(g for g in groups if g)

    if found:
        used[path.name] = found

all_used: set[str] = set().union(*used.values()) if used else set()
missing = sorted(all_used - defined)
unused = sorted(defined - all_used)

print(f"defined in L10n.Key : {len(defined)}")
for name, keys in used.items():
    print(f"  {name:26} references {len(keys):2}")

if missing:
    print(f"MISSING KEYS: {missing}")
    sys.exit(1)

print("ok: every referenced key exists in L10n.Key")

# Unused keys are not fatal - a table entry can be reached through a value the
# scanner cannot see - but an unexpected one is usually a rename that missed a
# call site, so surface it.
if unused:
    print(f"note: {len(unused)} key(s) referenced by no call site: {unused}")
