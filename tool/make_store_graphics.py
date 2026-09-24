#!/usr/bin/env python3
"""Store listing graphics for Google Play (and later the App Store).

- store/graphics/icon-512.png: the app icon at 512 x 512 (from assets/images/app_icon.png,
  which tool/make_app_icons.py makes).
- store/graphics/feature-graphic.png: 1024 x 500, the keyboard photo's logo with the ACE screen
  from store/screenshots/tablet-2-forth.png.
- store/screenshots/*.png: converted to 24-bit PNG (Play does not accept an alpha channel).

The screenshots themselves are taken from the running app on the emulators; see store/listing.md.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
PHOTO = ROOT / "archive/iACE/iACE/jupiterace@2x.jpg"
SHOTS = ROOT / "store/screenshots"
OUT = ROOT / "store/graphics"
OUT.mkdir(parents=True, exist_ok=True)

# Screenshots: drop alpha.
for shot in sorted(SHOTS.glob("*.png")):
    im = Image.open(shot)
    if im.mode != "RGB":
        im.convert("RGB").save(shot, optimize=True)

# Play's 7- and 10-inch tablet fields only take exactly 9:16. The tablet shots are 10:16
# (1600 x 2560), so they are scaled to 1440 wide and letterboxed in black to 1440 x 2560,
# rather than cropped (which would cut into the ACE screen).
TABLET_9X16 = ROOT / "store/screenshots/tablet-9x16"
TABLET_9X16.mkdir(exist_ok=True)
for shot in sorted(SHOTS.glob("tablet-*.png")):
    im = Image.open(shot).convert("RGB")
    w = 1440
    h = round(im.height * w / im.width)
    framed = Image.new("RGB", (1440, 2560), "black")
    framed.paste(im.resize((w, h), Image.LANCZOS), (0, (2560 - h) // 2))
    framed.save(TABLET_9X16 / f"{shot.stem}-9x16.png", optimize=True)

# Icon.
icon = Image.open(ROOT / "assets/images/app_icon.png").convert("RGB")
icon.resize((512, 512), Image.LANCZOS).save(OUT / "icon-512.png", optimize=True)

# Feature graphic: the case with the logo, and the ACE screen in a black bezel on the right.
W, H = 1024, 500
photo = Image.open(PHOTO).convert("RGB")
band = photo.crop((0, 0, photo.width, round(photo.width * H / W)))
feature = band.resize((W, H), Image.LANCZOS)

# The ACE screen area of the tablet screenshot: the widest 4:3 block of screen pixels.
tablet = Image.open(SHOTS / "tablet-2-forth.png").convert("RGB")
screen = tablet.crop((32, 90, 1568, 1242))  # 1536 x 1152, 6x the ACE's 256 x 192
screen_w, screen_h = 400, 300
screen = screen.resize((screen_w, screen_h), Image.LANCZOS)

pad = 14
box = (W - screen_w - 2 * pad - 40, (H - screen_h) // 2 - pad)
bezel = Image.new("RGB", (screen_w + 2 * pad, screen_h + 2 * pad), "black")
bezel.paste(screen, (pad, pad))

shadow = Image.new("L", (W, H), 0)
ImageDraw.Draw(shadow).rectangle(
    (box[0] + 6, box[1] + 10, box[0] + bezel.width + 6, box[1] + bezel.height + 10), fill=160
)
feature.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(10)))
feature.paste(bezel, box)
feature.save(OUT / "feature-graphic.png", optimize=True)

print("wrote", *(p.relative_to(ROOT) for p in sorted(OUT.iterdir())))
