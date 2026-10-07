#!/usr/bin/env python3
"""Builds assets/screenshots/tour.gif, the README's animated tour, from the ten page pictures screenshots.sh takes.

    ~/.venvs/upscale/bin/python assets/make-tour.py        (screenshots.sh runs it)

Each page stays SECONDS on screen, in the app's own page order, and the tour repeats. The frames keep the
pictures' full size: the README scales the tour to its column, and a click on it opens it full size. Each frame
has its own 256-colour palette (octree), which keeps the purple and the chart colours that a shared or
median-cut palette loses.
"""
import os
from PIL import Image

PAGES = ['home', 'fans', 'lighting', 'processor', 'graphics', 'displays', 'sensors', 'logging', 'alerts', 'activity']
SECONDS = 10
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'screenshots')

frames = [Image.open(os.path.join(D, p + '.png')).convert('RGB').quantize(colors=256, method=Image.FASTOCTREE, dither=Image.NONE) for p in PAGES]
out = os.path.join(D, 'tour.gif')
frames[0].save(out, save_all=True, append_images=frames[1:], duration=SECONDS * 1000, loop=0, optimize=True)
print('OK    assets/screenshots/tour.gif', frames[0].size, len(frames), 'pages,', SECONDS, 's each,', os.path.getsize(out) // 1024, 'KB')
