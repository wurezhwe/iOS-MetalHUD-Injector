"""Generate the app icon set for MetalHUD Launcher.

Draws a dark rounded tile with a GPU-style gauge arc and a live FPS readout,
matching the "metal performance HUD" idea without shipping artwork.
"""
from PIL import Image, ImageDraw

SIZE = 1024
BG_TOP = (18, 22, 30)
BG_BOTTOM = (34, 40, 56)
ACCENT = (94, 226, 255)
ACCENT_DIM = (58, 140, 168)
TEXT = (240, 248, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_icon(size):
    img = Image.new("RGB", (size, size), BG_TOP)
    px = img.load()
    for y in range(size):
        color = lerp(BG_TOP, BG_BOTTOM, y / max(1, size - 1))
        for x in range(size):
            px[x, y] = color

    draw = ImageDraw.Draw(img)
    unit = size / 1024.0

    # Gauge arc: a 270-degree sweep with a bright "current" segment.
    cx, cy = size / 2, size * 0.54
    radius = 330 * unit
    width = int(52 * unit)
    box = [cx - radius, cy - radius, cx + radius, cy + radius]
    draw.arc(box, start=135, end=405, fill=ACCENT_DIM, width=width)
    draw.arc(box, start=230, end=360, fill=ACCENT, width=width)

    # Tick marks around the arc.
    import math

    for i in range(13):
        angle = math.radians(135 + i * 22.5)
        r1 = radius - width
        r2 = radius - width - (26 if i % 3 == 0 else 15) * unit
        x1, y1 = cx + r1 * math.cos(angle), cy + r1 * math.sin(angle)
        x2, y2 = cx + r2 * math.cos(angle), cy + r2 * math.sin(angle)
        draw.line([x1, y1, x2, y2], fill=ACCENT if i % 3 == 0 else ACCENT_DIM,
                  width=int(9 * unit))

    # Centre readout bars (an abstract frame-time graph).
    bars = [70, 120, 96, 150, 110, 175, 130]
    bar_w = int(46 * unit)
    gap = int(22 * unit)
    total = len(bars) * bar_w + (len(bars) - 1) * gap
    start_x = cx - total / 2
    base_y = cy + 150 * unit
    for i, h in enumerate(bars):
        x0 = start_x + i * (bar_w + gap)
        y0 = base_y - h * unit
        draw.rounded_rectangle([x0, y0, x0 + bar_w, base_y],
                               radius=int(10 * unit), fill=ACCENT if i == 5 else TEXT)

    return img


def main():
    import os

    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(repo, "ios-app", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    master = make_icon(SIZE)
    master.save(os.path.join(out_dir, "AppIcon-1024.png"))
    print("wrote", os.path.join(out_dir, "AppIcon-1024.png"))

    # A marketing-sized copy for the README.
    master.resize((256, 256), Image.LANCZOS).save(os.path.join(repo, "icon.png"))


if __name__ == "__main__":
    main()
