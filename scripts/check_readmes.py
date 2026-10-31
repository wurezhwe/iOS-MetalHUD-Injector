"""Sanity-check the three README files: fence balance, language links, headings."""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FILES = ["README.md", "README.en.md", "README.zh-TW.md"]
FENCE = chr(96) * 3

ok = True
for name in FILES:
    path = REPO / name
    if not path.exists():
        print(f"MISSING {name}")
        ok = False
        continue

    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    # Only count fences and headings that are *outside* fenced blocks; the
    # directory tree contains "# build the IPA" style comments that would
    # otherwise be read as H1s.
    fences = 0
    h1 = 0
    h2 = 0
    inside = False
    for line in lines:
        if line.startswith(FENCE):
            fences += 1
            inside = not inside
            continue
        if inside:
            continue
        if line.startswith("# "):
            h1 += 1
        elif line.startswith("## "):
            h2 += 1

    links = {other: (other in text) for other in FILES if other != name}
    balanced = fences % 2 == 0

    status = "ok" if balanced and h1 == 1 else "BAD"
    if status == "BAD":
        ok = False

    print(
        f"{status:3} {name:16} lines={len(lines):4} fences={fences:3} "
        f"even={balanced!s:5} h1={h1} h2={h2:2} links={links}"
    )

sys.exit(0 if ok else 1)
