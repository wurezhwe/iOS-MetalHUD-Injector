"""Cross-check that every L10n key referenced from Swift code actually exists.

Two reference styles are used in the app:
  * `t(.someKey)` inside views
  * `return .someKey` inside the `localizationKey` computed properties of the
    HUD enums (Alignment / Layout / Metric)
Both are collected here and compared with the `case` list of `L10n.Key`.
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

used: dict[str, set[str]] = {}

for path in sorted(IOS.glob("*.swift")):
    text = path.read_text(encoding="utf-8")

    found: set[str] = set()
    # t(.key)  and  t(alignment.localizationKey) are handled by the enum scan.
    found.update(re.findall(r"\bt\(\.(\w+)\)", text))
    # `return .key` inside a localizationKey switch.
    found.update(re.findall(r"^            return \.(\w+)$", text, re.M))

    if found:
        used[path.name] = found

all_used: set[str] = set().union(*used.values()) if used else set()
missing = sorted(all_used - defined)

print(f"defined in L10n.Key : {len(defined)}")
for name, keys in used.items():
    print(f"  {name:26} references {len(keys):2}")

if missing:
    print(f"MISSING KEYS: {missing}")
    sys.exit(1)

print("ok: every referenced key exists in L10n.Key")
