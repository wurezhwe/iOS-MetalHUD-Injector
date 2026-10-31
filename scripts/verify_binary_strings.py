"""Byte-level check of the built IPA: confirms user-visible strings really shipped.

Decoding a Mach-O as UTF-8 mangles runs that sit next to non-UTF8 bytes, so
search for raw byte sequences instead.
"""
import sys
from pathlib import Path

REPO = Path(r"C:\Users\wuren\Documents\deepseek-harness\default-workspace\metalhud")

def main() -> int:
    bin_path = REPO / "dist" / "v12" / "Payload" / "MetalHUDLauncher.app" / "MetalHUDLauncher"
    if not bin_path.exists():
        print(f"missing {bin_path}")
        return 1

    blob = bin_path.read_bytes()

    needles = [
        # language names shown in the picker
        ("English", "utf-8"),
        ("简体中文", "utf-8"),
        ("繁體中文", "utf-8"),
        # one string from each table
        ("Pairing record loaded", "utf-8"),
        ("已载入配对记录", "utf-8"),
        ("已載入配對記錄", "utf-8"),
        # HUD option labels
        ("Enable Metal Performance HUD", "utf-8"),
        ("显示 Metal 性能 HUD", "utf-8"),
        ("顯示 Metal 效能 HUD", "utf-8"),
        # identifiers proving the new files compiled
        ("metalhud.language", "utf-8"),
        ("GameClassifier", "utf-8"),
        ("HUDAlignment", "utf-8"),
        ("glassEffect", "utf-8"),
        ("kCFStringTransformMandarinLatin", "utf-8"),
    ]

    ok = True
    for text, enc in needles:
        raw = text.encode(enc)
        count = blob.count(raw)
        mark = "ok  " if count else "MISS"
        if not count:
            ok = False
        print(f"{mark} {text!r:42} {count:3} hit(s)")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
