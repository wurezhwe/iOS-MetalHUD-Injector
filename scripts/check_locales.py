"""Check that the zh-TW and zh-CN READMEs do not leak each other's character set."""
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Simplified-only Hanzi that must never appear in the Traditional file.
# NB: characters that are identical in both scripts (式, 向, 除, 體 is not one
# of them) must NOT be listed here - only glyphs whose simplified form is
# genuinely different from the traditional one.
SIMPLIFIED_ONLY = (
    "设启应开执项删网务线电后载写图关区单测设备购买还为这从对导齐"
    "现复显进级传统样数据时间关闭选择确认编辑启动"
)
# Traditional-only Hanzi that must never appear in the Simplified file.
TRADITIONAL_ONLY = (
    "設啟應開執項刪網務線電後載寫圖關區單測設備購買還為這從對導齊"
    "現復顯進級傳統樣數據時間關閉選擇確認編輯啟動"
)


def scan(path: Path, forbidden: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")
    hits = sorted({ch for ch in text if ch in forbidden})
    if hits:
        print(f"LEAK {path.name}: {label} characters found: {''.join(hits)}")
        return False
    print(f"ok   {path.name}: no {label} characters")
    return True


def main() -> int:
    good = True
    good &= scan(REPO / "README.zh-TW.md", SIMPLIFIED_ONLY, "simplified-only")
    good &= scan(REPO / "README.md", TRADITIONAL_ONLY, "traditional-only")

    for name, needle in [
        ("README.md", "简体中文"),
        ("README.en.md", "English"),
        ("README.zh-TW.md", "繁體中文"),
    ]:
        text = (REPO / name).read_text(encoding="utf-8")
        present = needle in text
        print(f"{'ok  ' if present else 'MISS'} {name}: language label {needle!r}")
        good &= present

    return 0 if good else 1


if __name__ == "__main__":
    raise SystemExit(main())
