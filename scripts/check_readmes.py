"""Sanity-check the three README files: fence balance, language links, headings.

Also guards the iOS version table: Apple skipped from iOS 18 straight to iOS 26,
so any mention of iOS 19-25 is a factual error.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FILES = ["README.md", "README.en.md", "README.zh-TW.md"]
FENCE = chr(96) * 3

# "16–25", "19-25", "iOS 20" ... i.e. any range or single number in the
# non-existent gap. 26/27 are real, 18 and below are real.
PHANTOM_RANGE = re.compile(r"\b1[89]\s*[–\-~]\s*2[0-5]\b|\b2[0-5]\.x\b")

# A line that explicitly says these versions do not exist is correct prose, not
# an error - the READMEs explain the 18 -> 26 jump on purpose.
NEGATION = re.compile(
    r"不存在|没有|跳過|跳過|跳过|did not|does not|do not|never existed|skipped|skipping|不存在於"
)

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

    phantom = []
    for line in lines:
        if NEGATION.search(line):
            continue
        phantom.extend(PHANTOM_RANGE.findall(line))

    status = "ok" if balanced and h1 == 1 and not phantom else "BAD"
    if status == "BAD":
        ok = False

    print(
        f"{status:3} {name:16} lines={len(lines):4} fences={fences:3} "
        f"even={balanced!s:5} h1={h1} h2={h2:2} links={links}"
    )
    if phantom:
        print(f"    PHANTOM iOS VERSIONS (19-25 do not exist): {phantom}")

sys.exit(0 if ok else 1)
