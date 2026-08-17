#!/usr/bin/env python3
"""
Hangout brand mark — the "H monogram in a speech bubble" (concept #2).

The design is defined mathematically here rather than upscaled from a bitmap,
so every launcher density is rendered crisp from the same geometry. This
script is the single source of truth: it emits the launcher PNGs, the
adaptive-icon foregrounds, the master asset and a matching SVG.

Run:  python3 design/build_logo.py
"""
import math
import os
from PIL import Image, ImageDraw

# ── Brand geometry, expressed on a 1024x1024 grid ────────────────────────
S = 1024
TILE_RADIUS = 0.2344 * S          # 240/1024 — matches the app's rounded tiles

BUBBLE_CX, BUBBLE_CY = 0.500 * S, 0.4590 * S
BUBBLE_R = 0.2930 * S

# Speech-bubble tail (points down-left, like the original mark).
TAIL = [(0.3120, 0.6480), (0.2470, 0.8360), (0.4560, 0.6940)]

# The H: two stems + a crossbar, sized to sit optically centred in the bubble.
H_W, H_H, H_STROKE = 0.2440 * S, 0.2830 * S, 0.0645 * S

GRAD_FROM = (0x4F, 0x8D, 0xF8)    # AppColors.brandGradient start
GRAD_TO   = (0x25, 0x63, 0xEB)    # AppColors.brandGradient end
WHITE     = (255, 255, 255)

SS = 4  # supersampling factor for clean antialiased edges

# Fraction of the adaptive canvas the mark's ink should occupy. 0.62 keeps the
# glyph comfortably inside Android's 0.66 guaranteed-visible zone while still
# reading boldly next to other launcher icons.
ADAPTIVE_INK_FRACTION = 0.62


def _mark_ink_extent():
    """(top, bottom) of the mark's ink on the design grid, tail included."""
    top = BUBBLE_CY - BUBBLE_R
    bottom = max(BUBBLE_CY + BUBBLE_R, max(y for _, y in TAIL) * S)
    return top, bottom


def _diagonal_gradient(size):
    """Top-left → bottom-right linear gradient, matching the Flutter theme."""
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    denom = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / denom
            px[x, y] = (
                round(GRAD_FROM[0] + (GRAD_TO[0] - GRAD_FROM[0]) * t),
                round(GRAD_FROM[1] + (GRAD_TO[1] - GRAD_FROM[1]) * t),
                round(GRAD_FROM[2] + (GRAD_TO[2] - GRAD_FROM[2]) * t),
            )
    return grad


def _h_boxes(cx, cy, scale):
    """The three rectangles forming the H, as (x0, y0, x1, y1)."""
    w, h, st = H_W * scale, H_H * scale, H_STROKE * scale
    left, top = cx - w / 2, cy - h / 2
    return [
        (left, top, left + st, top + h),                       # left stem
        (left + w - st, top, left + w, top + h),               # right stem
        (left, cy - st / 2, left + w, cy + st / 2),            # crossbar
    ]


def _draw_mark(draw, cx, cy, scale, fill_bubble, fill_h):
    """Speech bubble + tail, with the H knocked out of it."""
    r = BUBBLE_R * scale
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill_bubble)
    draw.polygon(
        [(cx + (px - 0.5) * S * scale, cy + (py - BUBBLE_CY / S) * S * scale)
         for px, py in TAIL],
        fill=fill_bubble,
    )
    for box in _h_boxes(cx, cy, scale):
        draw.rectangle(box, fill=fill_h)


# How far the bubble centre must move so the mark's *ink* ends up centred.
# The tail hangs below the circle, so the circle sits slightly high. Measured
# in grid units relative to the bubble centre (negative = move up).
def _bubble_offset_from_ink_centre():
    top, bottom = _mark_ink_extent()
    return BUBBLE_CY - (top + bottom) / 2


# Scale that makes the mark's ink occupy ADAPTIVE_INK_FRACTION of the canvas.
def _adaptive_scale():
    top, bottom = _mark_ink_extent()
    return ADAPTIVE_INK_FRACTION / ((bottom - top) / S)


def render_icon(out_size, *, full_bleed=True, mark_scale=1.0, transparent=False):
    """
    full_bleed  : gradient tile fills the frame (legacy square launcher icon)
    transparent : no tile at all — used for the adaptive-icon foreground
    mark_scale  : shrinks the bubble (adaptive icons need a safe zone)
    """
    size = out_size * SS
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if not transparent:
        grad = _diagonal_gradient(size)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, size - 1, size - 1),
            radius=TILE_RADIUS * (size / S) if full_bleed else 0,
            fill=255,
        )
        canvas.paste(grad, (0, 0), mask)

    scale = (size / S) * mark_scale
    cx = size / 2
    # Place the bubble so the mark's overall ink is optically centred.
    cy = size / 2 + _bubble_offset_from_ink_centre() * scale

    if transparent:
        # Foreground layer: the bubble is white, the H is punched through to
        # transparent so the adaptive background colour shows through.
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        r = BUBBLE_R * scale
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE + (255,))
        d.polygon(
            [(cx + (px - 0.5) * S * scale, cy + (py - BUBBLE_CY / S) * S * scale)
             for px, py in TAIL],
            fill=WHITE + (255,),
        )
        for box in _h_boxes(cx, cy, scale):
            d.rectangle(box, fill=(0, 0, 0, 0))
        canvas.alpha_composite(layer)
    else:
        d = ImageDraw.Draw(canvas)
        # Sample the gradient under the H so the knockout matches the tile.
        h_colour = _diagonal_gradient(size).getpixel((int(cx), int(cy)))
        _draw_mark(d, cx, cy, scale, WHITE + (255,), h_colour + (255,))

    return canvas.resize((out_size, out_size), Image.LANCZOS)


def build_svg():
    """Hand-written vector twin of the geometry above."""
    cx, cy, r = BUBBLE_CX, BUBBLE_CY, BUBBLE_R
    tail = " ".join(f"{x * S:.1f},{y * S:.1f}" for x, y in TAIL)
    boxes = "\n".join(
        f'  <rect x="{x0:.1f}" y="{y0:.1f}" width="{x1 - x0:.1f}" '
        f'height="{y1 - y0:.1f}" fill="url(#bg)"/>'
        for x0, y0, x1, y1 in _h_boxes(cx, cy, 1.0)
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="{S}" y2="{S}" gradientUnits="userSpaceOnUse">
      <stop stop-color="#{GRAD_FROM[0]:02X}{GRAD_FROM[1]:02X}{GRAD_FROM[2]:02X}"/>
      <stop offset="1" stop-color="#{GRAD_TO[0]:02X}{GRAD_TO[1]:02X}{GRAD_TO[2]:02X}"/>
    </linearGradient>
  </defs>
  <rect width="{S}" height="{S}" rx="{TILE_RADIUS:.0f}" fill="url(#bg)"/>
  <circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="#FFFFFF"/>
  <polygon points="{tail}" fill="#FFFFFF"/>
{boxes}
</svg>
'''


ADAPTIVE_SCALE = _adaptive_scale()


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    res = os.path.join(root, "hangout_app", "android", "app", "src", "main", "res")

    # Legacy square/round launcher icons.
    for folder, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                       ("xxhdpi", 144), ("xxxhdpi", 192)]:
        icon = render_icon(px)
        for name in ("ic_launcher.png", "ic_launcher_round.png"):
            path = os.path.join(res, f"mipmap-{folder}", name)
            icon.save(path)
            print("wrote", os.path.relpath(path, root))

    # Adaptive-icon foregrounds. Android reserves the outer ~33% of the
    # 108dp canvas: only the centre 66% is guaranteed visible once a launcher
    # applies its mask (circle, squircle, teardrop...). The mark's own ink is
    # ~0.67 of the design grid, so scale it to land just inside that zone.
    for folder, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216),
                       ("xxhdpi", 324), ("xxxhdpi", 432)]:
        fg = render_icon(px, transparent=True, mark_scale=ADAPTIVE_SCALE)
        path = os.path.join(res, f"mipmap-{folder}", "ic_launcher_foreground.png")
        fg.save(path)
        print("wrote", os.path.relpath(path, root))

    # Master assets.
    assets = os.path.join(root, "hangout_app", "assets")
    render_icon(1024).save(os.path.join(assets, "app_icon.png"))
    print("wrote hangout_app/assets/app_icon.png")
    with open(os.path.join(assets, "app_icon.svg"), "w") as fh:
        fh.write(build_svg())
    print("wrote hangout_app/assets/app_icon.svg")

    # Store / marketing master.
    out = os.path.join(root, "design", "logo_master_1024.png")
    render_icon(1024).save(out)
    print("wrote design/logo_master_1024.png")
