#!/usr/bin/env python3
"""Generate the MyOpenScale app icon (iOS 26): Mochi, the app's squishy
talking-scale companion, waving hello.

Mochi is drawn from the same 200x200 design space as `App/Mochi/MochiView.swift`
(dome body in Theme.accent, antenna with a yellow bulb, blush, tummy display)
and centred on a soft background. Three appearance variants are emitted for the
iOS 26 layered/Liquid Glass icon system:

  * light   — soft mint -> sky gradient, green Mochi (the default look)
  * dark    — deep teal -> navy gradient, green Mochi (Dark appearance)
  * tinted  — grayscale on near-black so the system can apply the user's tint

Each is rendered at 4x and downsampled for clean anti-aliasing. Output is a
full-bleed 1024x1024 PNG with no alpha; iOS applies the rounded-superellipse
mask and the Liquid Glass specular treatment itself. The light variant is also
written to the Watch app's icon.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

# --- palette (matches App/Theme.swift and MochiView) ------------------------
ACCENT      = (33, 184, 140)    # Theme.accent
ACCENT_DEEP = (23, 143, 108)    # arm / shading green
BULB        = (255, 209, 102)   # #FFD166
BLUSH       = (255, 143, 163)   # #FF8FA3
INK         = (29, 43, 54)      # #1D2B36 face
DISPLAY     = (244, 255, 251)   # tummy display

VARIANTS = {
    "light":  {"bg": ((226, 248, 239), (214, 236, 252)), "body": ACCENT, "arm": ACCENT,
               "bulb": BULB, "blush": BLUSH, "ink": INK, "display": DISPLAY, "shadow": (0, 0, 0, 34)},
    "dark":   {"bg": ((9, 46, 38), (12, 30, 56)), "body": ACCENT, "arm": ACCENT,
               "bulb": BULB, "blush": BLUSH, "ink": INK, "display": DISPLAY, "shadow": (0, 0, 0, 90)},
    "tinted": {"bg": ((14, 16, 18), (32, 36, 40)), "body": (205, 205, 205), "arm": (205, 205, 205),
               "bulb": (245, 245, 245), "blush": (170, 170, 170), "ink": (40, 40, 40),
               "display": (245, 245, 245), "shadow": (0, 0, 0, 90)},
}

S = 1024            # final size
SS = 4              # supersample factor
N = S * SS          # working size

# Mochi's 200x200 design space -> canvas: scale and offset so the figure
# (incl. the waving arm and the antenna) sits centred with breathing room.
K = N / 200 * 0.82
OX = N / 2 - 100 * K
OY = N / 2 - 106 * K

ICON_DIR = "App/Assets.xcassets/AppIcon.appiconset"
WATCH_DIR = "Watch/Assets.xcassets/AppIcon.appiconset"


def P(x, y):
    """Design-space point -> canvas point."""
    return (OX + x * K, OY + y * K)


def quad(p0, c, p1, steps=48):
    """Sample a quadratic Bézier (design space) into canvas points."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1]
        pts.append(P(x, y))
    return pts


def stroke(draw, pts, width, fill):
    """Round-capped stroke, width in design units: a dense sweep of discs, which
    stays smooth on tight curves where a thick `line` shows seams."""
    r = width * K / 2
    dense = []
    for (a, b) in zip(pts, pts[1:]):
        steps = max(1, int(((b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2) ** 0.5 / (r / 4)))
        dense += [(a[0] + (b[0] - a[0]) * i / steps, a[1] + (b[1] - a[1]) * i / steps) for i in range(steps)]
    dense.append(pts[-1])
    for (x, y) in dense:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def ellipse(draw, cx, cy, rx, ry, fill):
    x0, y0 = P(cx - rx, cy - ry)
    x1, y1 = P(cx + rx, cy + ry)
    draw.ellipse((x0, y0, x1, y1), fill=fill)


def diagonal_gradient(size, c0, c1):
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(0, size, 4):
            t = (x + y) / (2 * (size - 1))
            c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
            for dx in range(4):
                if x + dx < size:
                    px[x + dx, y] = c
    return grad


def render(spec):
    img = diagonal_gradient(N, *spec["bg"]).convert("RGBA")

    # Soft ground shadow.
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ellipse(ImageDraw.Draw(shadow), 100, 184, 64, 8, spec["shadow"])
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(N / 160)))

    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Right arm resting at the side (drawn behind the body).
    stroke(d, quad((166, 132), (182, 140), (180, 154)), 13, spec["arm"])
    # Left arm waving hello (raised).
    stroke(d, quad((36, 124), (14, 106), (20, 82)), 13, spec["arm"])

    # Antenna + bulb.
    stroke(d, quad((100, 62), (98, 40), (110, 34)), 6, spec["body"])
    ellipse(d, 112, 32, 9, 9, spec["bulb"])

    # Dome body: M30 150 Q22 70 100 60 Q178 70 170 150 Q168 176 100 176 Q32 176 30 150 Z
    body = (quad((30, 150), (22, 70), (100, 60)) + quad((100, 60), (178, 70), (170, 150))
            + quad((170, 150), (168, 176), (100, 176)) + quad((100, 176), (32, 176), (30, 150)))
    d.polygon(body, fill=spec["body"])

    # Glossy highlight along the top-left of the dome.
    sheen = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    stroke(ImageDraw.Draw(sheen), quad((48, 96), (70, 70), (100, 68)), 9, (255, 255, 255, 90))
    layer.alpha_composite(sheen)

    # Face: big sparkly eyes, open smile, blush.
    for cx in (78, 122):
        ellipse(d, cx, 110, 9, 9, spec["ink"])
        ellipse(d, cx + 3, 106, 3.2, 3.2, (255, 255, 255, 255))
        ellipse(d, cx - 3, 113, 1.4, 1.4, (255, 255, 255, 255))
    d.polygon(quad((86, 126), (100, 146), (114, 126)), fill=spec["ink"])
    tongue = quad((92, 136), (100, 145), (108, 136)) + quad((108, 136), (100, 131), (92, 136))
    d.polygon(tongue, fill=spec["blush"])
    blush = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blush)
    ellipse(bd, 60, 130, 10, 6, spec["blush"] + (200,))
    ellipse(bd, 140, 130, 10, 6, spec["blush"] + (200,))
    layer.alpha_composite(blush)

    # Tummy display pill.
    x0, y0 = P(72, 151)
    x1, y1 = P(128, 164)
    d.rounded_rectangle((x0, y0, x1, y1), radius=(y1 - y0) / 2, fill=spec["display"])

    img.alpha_composite(layer)
    return img.convert("RGB").resize((S, S), Image.LANCZOS)


def main():
    names = {"light": "AppIcon-1024.png", "dark": "AppIcon-Dark-1024.png",
             "tinted": "AppIcon-Tinted-1024.png"}
    rendered = {}
    for variant, spec in VARIANTS.items():
        out = render(spec)
        out.save(os.path.join(ICON_DIR, names[variant]))
        rendered[variant] = out
    rendered["light"].save(os.path.join(WATCH_DIR, "AppIcon-1024.png"))

    preview = Image.new("RGB", (1024 * 3 + 48, 1024), (255, 255, 255))
    for i, variant in enumerate(("light", "dark", "tinted")):
        preview.paste(rendered[variant], (i * (1024 + 24), 0))
    preview.resize((384 * 3 + 18, 384), Image.LANCZOS).save("scripts/icon_preview.png")


if __name__ == "__main__":
    main()
