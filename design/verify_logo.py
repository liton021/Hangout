#!/usr/bin/env python3
"""Renders a proof sheet of the launcher icon as Android will actually mask it."""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RES = os.path.join(ROOT, "hangout_app/android/app/src/main/res")
BG = "#2E77F0"  # values/colors.xml launcher_background

def font(sz, bold=False):
    f = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    try: return ImageFont.truetype(f"/usr/share/fonts/truetype/dejavu/{f}", sz)
    except Exception: return ImageFont.load_default()

def composed(px):
    """Adaptive icon = background colour + foreground layer, then masked."""
    fg = Image.open(f"{RES}/mipmap-xxxhdpi/ic_launcher_foreground.png").convert("RGBA")
    fg = fg.resize((px, px), Image.LANCZOS)
    base = Image.new("RGBA", (px, px), BG)
    base.alpha_composite(fg)
    return base

def mask(im, shape):
    px = im.size[0]
    m = Image.new("L", (px, px), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse((0, 0, px-1, px-1), fill=255)
    elif shape == "squircle":
        d.rounded_rectangle((0, 0, px-1, px-1), radius=px*0.30, fill=255)
    elif shape == "rounded":
        d.rounded_rectangle((0, 0, px-1, px-1), radius=px*0.16, fill=255)
    else:
        d.rectangle((0, 0, px-1, px-1), fill=255)
    out = Image.new("RGB", (px, px), "#F4F5F8")
    out.paste(im.convert("RGB"), (0, 0), m)
    return out

W, H = 1180, 640
sheet = Image.new("RGB", (W, H), "#F4F5F8")
d = ImageDraw.Draw(sheet)
d.text((40, 30), "Hangout icon — launcher mask proof", font=font(34, True), fill="#0F1115")
d.text((40, 74), "Adaptive icon composed from ic_launcher_foreground + launcher_background, "
                 "then masked as real launchers do.", font=font(17), fill="#6B7280")

# Row 1: adaptive masks at a large size.
big = 200
for i, shape in enumerate(["circle", "squircle", "rounded", "square"]):
    x = 40 + i * (big + 42)
    sheet.paste(mask(composed(big), shape), (x, 120))
    d.text((x, 120 + big + 12), shape, font=font(19, True), fill="#0F1115")

# Row 2: real launcher sizes.
d.text((40, 400), "Actual size on a phone home screen:", font=font(19, True), fill="#0F1115")
x = 40
for px, label in [(48, "48dp mdpi"), (72, "72dp hdpi"), (96, "96dp xhdpi"), (144, "144dp xxhdpi")]:
    sheet.paste(mask(composed(px), "circle"), (x, 440))
    d.text((x, 440 + px + 8), label, font=font(14), fill="#6B7280")
    x += px + 56

# Legacy square icon for comparison.
legacy = Image.open(f"{RES}/mipmap-xxxhdpi/ic_launcher.png").convert("RGB").resize((96, 96), Image.LANCZOS)
sheet.paste(legacy, (x + 30, 440))
d.text((x + 30, 440 + 96 + 8), "legacy ic_launcher", font=font(14), fill="#6B7280")

out = os.path.join(ROOT, "design", "icon_proof.png")
sheet.save(out, quality=95)
print("wrote design/icon_proof.png")
