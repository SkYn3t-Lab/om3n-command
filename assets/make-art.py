#!/usr/bin/env python3
"""Builds the two pictures the app's sidebar shows, from the owner's banner and icon image.

  make-art.py [preview.png]        run in this folder

om3n-command-wordmark.png  the "Om3n Command" lettering cut out of om3n-command-banner.jpg
om3n-command-figure.png    the hooded figure from om3n-command-512.png, fading out towards the top

Both sources sit on near-black, so the background is removed by brightness: a pixel is as opaque as its brightest
channel, which keeps the red glow round the lettering and the smoke round the figure and lets the app's own
background show through everywhere else. The preview lays both on the app's sidebar colour.
"""
import sys
from PIL import Image, ImageChops

SIDEBAR = (7, 5, 11, 255)

def cut_out(img, floor, span):
    """Alpha from the brightest channel: 0 at `floor`, full at `floor + span`."""
    r, g, b = img.convert('RGB').split()
    peak = ImageChops.lighter(ImageChops.lighter(r, g), b)
    alpha = peak.point(lambda v: max(0, min(255, (v - floor) * 255 // span)))
    out = img.convert('RGBA')
    out.putalpha(alpha)
    return out

banner = Image.open('om3n-command-banner.jpg')
word = cut_out(banner.crop((40, 150, 730, 560)), 16, 70)
word = word.crop(word.getchannel('A').point(lambda v: 255 if v > 40 else 0).getbbox())
word.save('om3n-command-wordmark.png')

fig = cut_out(Image.open('om3n-command-512.png'), 10, 90)
w, h = fig.size
fade = Image.new('L', (1, h))
fade.putdata([min(255, int(255 * (y / (h * 0.55)) ** 1.5)) for y in range(h)])
fig.putalpha(ImageChops.multiply(fig.getchannel('A'), fade.resize((w, h))))
fig.save('om3n-command-figure.png')

for name in ('om3n-command-wordmark.png', 'om3n-command-figure.png'):
    i = Image.open(name)
    lo, hi = i.getchannel('A').getextrema()
    print(f'{name}: {i.size[0]} x {i.size[1]}, {i.mode}, alpha {lo} to {hi}')
    assert i.mode == 'RGBA' and lo == 0 and hi == 255

if len(sys.argv) > 1:
    sheet = Image.new('RGBA', (400, 900), SIDEBAR)
    small = word.resize((300, word.size[1] * 300 // word.size[0]), Image.LANCZOS)
    sheet.alpha_composite(small, (50, 40))
    sheet.alpha_composite(fig.resize((400, 400), Image.LANCZOS), (0, 500))
    sheet.save(sys.argv[1])
