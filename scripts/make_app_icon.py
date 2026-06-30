#!/usr/bin/env python3
"""Generate the MiScaleApp Liquid Glass app icon (iOS 26).

A white weighing-scale dial (arc + ticks + needle + hub) over the app's
signature green->blue health gradient (Theme.accent -> Theme.accentSecondary).
Three appearance variants are emitted for the iOS 26 layered/Liquid Glass icon
system:

  * light   — green->blue gradient, white dial (the default look)
  * dark    — deep teal->navy gradient, white dial (Dark appearance)
  * tinted  — grayscale on near-black so the system can apply the user's tint

Each is rendered at 4x and downsampled for clean anti-aliasing. Output is a
full-bleed 1024x1024 PNG with no alpha; iOS applies the rounded-superellipse
mask and the Liquid Glass specular treatment itself.
"""
import math
import os
from PIL import Image, ImageDraw

# --- palette (matches App/Theme.swift) -------------------------------------
ACCENT     = (33, 184, 140)   # 0.13, 0.72, 0.55
ACCENT_2   = (51, 140, 217)   # 0.20, 0.55, 0.85
DARK_GREEN = (9, 46, 38)      # deep teal for the dark variant
DARK_BLUE  = (12, 30, 56)     # deep navy for the dark variant
NEAR_BLACK = (14, 16, 18)
GRAY_BG    = (32, 36, 40)
WHITE      = (255, 255, 255)

S  = 1024          # final size
SS = 4             # supersample factor
N  = S * SS        # working size

OUT_DIR = "App/Assets.xcassets/AppIcon.appiconset"

VARIANTS = {
    "light":  {"bg": (ACCENT, ACCENT_2),       "fg": WHITE,           "sheen": 70, "hub": ACCENT},
    "dark":   {"bg": (DARK_GREEN, DARK_BLUE),   "fg": (240, 244, 246), "sheen": 46, "hub": ACCENT},
    "tinted": {"bg": (NEAR_BLACK, GRAY_BG),     "fg": WHITE,           "sheen": 30, "hub": (210, 210, 210)},
}


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


def render(variant: str, spec: dict) -> Image.Image:
    c0, c1 = spec["bg"]
    fg = spec["fg"]

    # Background gradient (built small, then scaled up — it's smooth anyway).
    g = diagonal_gradient(256, c0, c1).resize((N, N), Image.BICUBIC)
    img = g.convert("RGBA")

    # Soft radial sheen near the top-left for a little depth / glassiness.
    sheen = Image.new("L", (N, N), 0)
    sd = ImageDraw.Draw(sheen)
    cx, cy, rad = N * 0.32, N * 0.26, N * 0.62
    sd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=spec["sheen"])
    img = Image.composite(Image.new("RGBA", (N, N), (255, 255, 255, 255)), img, sheen)

    d = ImageDraw.Draw(img)

    # --- gauge geometry ----------------------------------------------------
    gcx, gcy = N / 2, N * 0.555            # dial centre (nudged down a touch)
    R = N * 0.300                          # arc radius
    width = N * 0.052                      # arc stroke width
    start, end = 150, 390                  # sweep over the top, open at bottom

    bbox = [gcx - R, gcy - R, gcx + R, gcy + R]
    d.arc(bbox, start, end, fill=fg, width=int(width))

    # Rounded caps on the arc ends.
    for ang in (start, end):
        ex = gcx + R * math.cos(math.radians(ang))
        ey = gcy + R * math.sin(math.radians(ang))
        r = width / 2
        d.ellipse([ex - r, ey - r, ex + r, ey + r], fill=fg)

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
        d.line([x0, y0, x1, y1], fill=fg, width=t_w)
        cap = t_w / 2
        for (px_, py_) in ((x0, y0), (x1, y1)):
            d.ellipse([px_ - cap, py_ - cap, px_ + cap, py_ + cap], fill=fg)

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
    tail_r = R * 0.16                       # short tail behind the hub
    tailx = gcx - tail_r * math.cos(needle_ang)
    taily = gcy - tail_r * math.sin(needle_ang)
    d.polygon([(tipx, tipy), (bx, by), (tailx, taily), (bx2, by2)], fill=fg)

    # Centre hub: light disc with a tinted core.
    hub = width * 1.15
    d.ellipse([gcx - hub, gcy - hub, gcx + hub, gcy + hub], fill=fg)
    core = hub * 0.46
    d.ellipse([gcx - core, gcy - core, gcx + core, gcy + core], fill=spec["hub"])

    return img.convert("RGB").resize((S, S), Image.LANCZOS)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    names = {"light": "AppIcon-1024.png",
             "dark": "AppIcon-Dark-1024.png",
             "tinted": "AppIcon-Tinted-1024.png"}
    preview = Image.new("RGB", (S * 3 + 48, S), (255, 255, 255))
    for i, (variant, spec) in enumerate(VARIANTS.items()):
        out = render(variant, spec)
        out.save(os.path.join(OUT_DIR, names[variant]))
        preview.paste(out, (i * (S + 24), 0))
        print("wrote", names[variant])
    preview.resize((384 * 3 + 18, 384), Image.LANCZOS).save("scripts/icon_preview.png")
    print("wrote scripts/icon_preview.png")


if __name__ == "__main__":
    main()
