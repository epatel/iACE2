#!/usr/bin/env python3
"""Generate the app icons: the top-left square of the Jupiter ACE keyboard photo (logo, stripes and
the first keys) tinted light blue, the look of the iACE 1.x App Store icon, but rebuilt from the
2x photo so it is sharp at 1024 px.

Writes every size listed in the iOS AppIcon set and the Android launcher mipmaps.
"""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHOTO = ROOT / "archive/iACE/iACE/jupiterace@2x.jpg"
TINT = (170 / 255, 220 / 255, 245 / 255)  # white becomes the original icon's light blue

photo = Image.open(PHOTO).convert("RGB")
side = 930  # 465 px of the 1x photo: the logo, the stripes and keys 1 to 7, like the original icon
icon = photo.crop((0, 0, side, side)).resize((1024, 1024), Image.LANCZOS)
r, g, b = icon.split()
icon = Image.merge(
    "RGB",
    [c.point(lambda v, t=t: int(v * t)) for c, t in zip((r, g, b), TINT)],
)

ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for entry in json.loads((ios / "Contents.json").read_text())["images"]:
    size = float(entry["size"].split("x")[0]) * float(entry["scale"].rstrip("x"))
    icon.resize((round(size), round(size)), Image.LANCZOS).save(ios / entry["filename"])

android = ROOT / "android/app/src/main/res"
for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    icon.resize((size, size), Image.LANCZOS).save(android / f"mipmap-{density}/ic_launcher.png")

icon.save(ROOT / "assets/images/app_icon.png")
print("wrote iOS and Android app icons")
