#!/usr/bin/env python3
"""Draws the Shofha app icon (1024x1024) — run in CI before xcodebuild.

Design: diagonal violet->cyan gradient, white disc, violet play triangle.
The PNG is generated, never committed (push tooling is text-only).
"""
import os
from PIL import Image, ImageDraw

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), "..",
                   "ShofhaApp", "Assets.xcassets", "AppIcon.appiconset",
                   "icon-1024.png")

VIOLET = (124, 92, 255)   # #7c5cff
CYAN = (0, 194, 255)      # #00c2ff
WHITE = (255, 255, 255)

# Diagonal gradient: build small, upscale for smoothness.
small = Image.new("RGB", (256, 256))
px = small.load()
for y in range(256):
    for x in range(256):
        t = (x + y) / 510.0
        px[x, y] = tuple(int(VIOLET[i] + (CYAN[i] - VIOLET[i]) * t) for i in range(3))
img = small.resize((SIZE, SIZE), Image.BICUBIC)

d = ImageDraw.Draw(img)
# White disc, centered, ~62% of the icon.
r = int(SIZE * 0.31)
c = SIZE // 2
d.ellipse([c - r, c - r, c + r, c + r], fill=WHITE)
# Play triangle in violet, optically centered (shifted right a touch).
tx, ty = c + int(SIZE * 0.02), c
w, h = int(SIZE * 0.16), int(SIZE * 0.19)
d.polygon([(tx - w // 2, ty - h // 2),
           (tx - w // 2, ty + h // 2),
           (tx + w // 2, ty)], fill=VIOLET)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, "PNG")
print("icon written:", OUT, img.size)
