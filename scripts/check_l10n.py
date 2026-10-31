"""Verify the in-app localization tables are complete.

L10n.swift deliberately avoids .strings files so the whole table is reviewable
in one place; that tradeoff only pays off if completeness is checked. This
parses the Swift source and asserts every L10n.Key has an entry in the English,
Simplified and Traditional tables.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "ios-app" / "L10n.swift"

TABLE_NAMES = ["english", "simplified", "traditional"]


def parse_tables(text: str) -> tuple[list[str], dict[str, set[str]]]:
    key_block = re.search(r"enum Key: String, CaseIterable \{(.*?)\n    \}", text, re.S)
    if not key_block:
        raise SystemExit("could not locate the L10n.Key enum")
    # `case foo` lines, ignoring the doc comments in between
    keys = re.findall(r"^\s+case (\w+)\s*$", key_block.group(1), re.M)

    tables: dict[str, set[str]] = {}
    for name in TABLE_NAMES:
        block = re.search(
            r"private static let " + name + r": \[Key: String\] = \[(.*?)\n    \]",
            text,
            re.S,
        )
        if not block:
            raise SystemExit(f"could not locate table {name}")
        tables[name] = set(re.findall(r"\.(\w+):", block.group(1)))
    return keys, tables


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    keys, tables = parse_tables(text)

    print(f"{len(keys)} keys declared in L10n.Key")
    ok = True

    for name in TABLE_NAMES:
        entries = tables[name]
        missing = [k for k in keys if k not in entries]
        extra = sorted(entries - set(keys))
        status = "ok  " if not missing and not extra else "BAD "
        print(f"{status} {name:12} {len(entries):3} entries"
              f"  missing={missing or 'none'}  unknown={extra or 'none'}")
        if missing or extra:
            ok = False

    # Guard against the same string being pasted into a table twice with
    # different keys - a copy/paste slip that reads fine but is wrong.
    if len(set(keys)) != len(keys):
        print("BAD  duplicate keys in L10n.Key")
        ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
