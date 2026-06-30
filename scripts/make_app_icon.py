#!/usr/bin/env python3
"""Generate the MiScaleApp app icon.

A white scale-dial gauge (arc + ticks + needle + hub) reading as a weighing
scale, set over the app's signature green->blue health gradient
(Theme.accent -> Theme.accentSecondary). Rendered at 4x and downsampled for
clean anti-aliasing. Output is a full-bleed 1024x1024 PNG; iOS applies the
rounded-superellipse mask itself.
"""
import math
from PIL import Image, ImageDraw

# --- palette (matches App/Theme.swift) -------------------------------------
ACCENT      = (33, 184, 140)   # 0.13, 0.72, 0.55
ACCENT_2    = (51, 140, 217)   # 0.20, 0.55, 0.85
ACCENT_DARK = (18, 120, 96)    # deeper green for gradient depth
WHITE       = (255, 255, 255)

S  = 1024          # final size
SS = 4             # supersample factor
N  = S * SS        # working size


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, c0, c1):
    """Smooth top-left -> bottom-right gradient."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    maxd = (size - 1) * 2
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(c0, c1, (x + y) / maxd)
    return img


def main():
    # Background gradient (built small, then scaled up — it's smooth anyway).
    g = diagonal_gradient(256, ACCENT, ACCENT_2).resize((N, N), Image.BICUBIC)
    img = g.convert("RGBA")
    d = ImageDraw.Draw(img)

    # Soft radial sheen near the top-left for a little depth.
    sheen = Image.new("L", (N, N), 0)
    sd = ImageDraw.Draw(sheen)
    cx, cy, rad = N * 0.32, N * 0.26, N * 0.62
    sd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=70)
    white_layer = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    img = Image.composite(white_layer, img, sheen)

    d = ImageDraw.Draw(img)

    # --- gauge geometry ----------------------------------------------------
    gcx, gcy = N / 2, N * 0.555           # dial centre (nudged down a touch)
    R = N * 0.300                          # arc radius
    width = N * 0.052                      # arc stroke width
    start, end = 150, 390                  # sweep over the top, open at bottom

    bbox = [gcx - R, gcy - R, gcx + R, gcy + R]
    d.arc(bbox, start, end, fill=WHITE, width=int(width))

    # Rounded caps on the arc ends.
    for ang in (start, end):
        ex = gcx + R * math.cos(math.radians(ang))
        ey = gcy + R * math.sin(math.radians(ang))
        r = width / 2
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=WHITE)

    # --- tick marks along the dial ----------------------------------------
    n_ticks = 9
    for i in range(n_ticks):
        ang = math.radians(start + (end - start) * i / (n_ticks - 1))
        major = (i % 2 == 0)
        t_len = R * (0.20 if major else 0.12)
        t_w = int(width * (0.34 if major else 0.22))
        r_out = R - width * 0.62
        r_in = r_out - t_len
        x0 = gcx + r_in * math.cos(ang)
        y0 = gcy + r_in * math.sin(ang)
        x1 = gcx + r_out * math.cos(ang)
        y1 = gcy + r_out * math.sin(ang)
        d.line([x0, y0, x1, y1], fill=WHITE, width=t_w)
        cap = t_w / 2
        for (px_, py_) in ((x0, y0), (x1, y1)):
            d.ellipse([px_ - cap, py_ - cap, px_ + cap, py_ + cap], fill=WHITE)

    # --- needle (points up-right, like a live reading) --------------------
    needle_ang = math.radians(312)         # ~1 o'clock
    tip_r = R * 0.86
    base_w = width * 0.85
    tipx = gcx + tip_r * math.cos(needle_ang)
    tipy = gcy + tip_r * math.sin(needle_ang)
    perp = needle_ang + math.pi / 2
    bx = gcx + (base_w / 2) * math.cos(perp)
    by = gcy + (base_w / 2) * math.sin(perp)
    bx2 = gcx - (base_w / 2) * math.cos(perp)
    by2 = gcy - (base_w / 2) * math.sin(perp)
    # short tail behind the hub for balance
    tail_r = R * 0.16
    tailx = gcx - tail_r * math.cos(needle_ang)
    taily = gcy - tail_r * math.sin(needle_ang)
    d.polygon([(tipx, tipy), (bx, by), (tailx, taily), (bx2, by2)], fill=WHITE)

    # Centre hub: white disc with a gradient-coloured core.
    hub = width * 1.15
    d.ellipse([gcx - hub, gcy - hub, gcx + hub, gcy + hub], fill=WHITE)
    core = hub * 0.46
    d.ellipse([gcx - core, gcy - core, gcx + core, gcy + core], fill=ACCENT)

    # --- downsample & save -------------------------------------------------
    out = img.convert("RGB").resize((S, S), Image.LANCZOS)
    out.save("App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
    # Handy preview at display size.
    out.resize((256, 256), Image.LANCZOS).save("scripts/icon_preview.png")
    print("wrote AppIcon-1024.png")


if __name__ == "__main__":
    main()
