#!/usr/bin/env python3
"""Builds om3n-command.ico from the owner's 512 px image (om3n-command-512.png).

  make-icon.py <source.png> [preview.png]

As the owner asked: the whole image at every size (no head crop), with the bottom trimmed slightly, a rounded edge and
a slight sharpen. The trim takes TRIM px off the bottom and half of that off each side, so it stays square and the
figure stays centred. The rounded corners
have real transparency and are drawn at 4x then scaled down, so the edge is smooth. Sizes of 64 px and below get a
light unsharp mask. Every entry is read back and compared with what was meant to go in.
"""
import sys
from PIL import Image, ImageDraw, ImageFilter

src = Image.open(sys.argv[1]).convert('RGBA')
assert src.size == (512, 512), src.size
TRIM = 40
base = src.crop((TRIM // 2, 0, 512 - TRIM // 2, 512 - TRIM))
assert base.size[0] == base.size[1], base.size
SIZES = [16, 24, 32, 48, 64, 128, 256]

def entry(s):
    big = base.resize((s * 4, s * 4), Image.LANCZOS)
    mask = Image.new('L', (s * 4, s * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * 0.22), fill=255)
    big.putalpha(mask)
    out = big.resize((s, s), Image.LANCZOS)
    if s <= 64:
        rgb = out.convert('RGB').filter(ImageFilter.UnsharpMask(radius=0.8, percent=90, threshold=2))
        rgb.putalpha(out.getchannel('A'))
        out = rgb
    return out

want = {s: entry(s) for s in SIZES}
want[256].save('om3n-command.ico', sizes=[(s, s) for s in SIZES], append_images=[want[s] for s in SIZES if s != 256])

got = sorted(Image.open('om3n-command.ico').info['sizes'])
assert got == [(s, s) for s in SIZES], got
for s in SIZES:
    c = Image.open('om3n-command.ico')
    c.size = (s, s)
    c = c.convert('RGBA')
    same = c.tobytes() == want[s].tobytes()
    corner, centre = c.getpixel((0, 0))[3], c.getpixel((s // 2, s // 2))[3]
    print(f'{s:>3} px: whole image, read back identical = {same}, corner alpha {corner}, centre alpha {centre}')
    assert same and corner <= 16 and centre == 255   # a few alpha units of scaling ripple at the very corner are fine

if len(sys.argv) > 2:
    sheet = Image.new('RGBA', (40 + sum(s + 20 for s in SIZES), 2 * 276 + 20), (0, 0, 0, 0))
    for row, bg in enumerate(((32, 34, 40, 255), (225, 228, 235, 255))):
        ImageDraw.Draw(sheet).rectangle((0, row * 286, sheet.width, row * 286 + 276), fill=bg)
        x = 20
        for s in SIZES:
            sheet.alpha_composite(want[s], (x, row * 286 + 10 + (256 - s)))
            x += s + 20
    sheet.save(sys.argv[2])
