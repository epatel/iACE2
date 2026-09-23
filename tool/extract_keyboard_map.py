#!/usr/bin/env python3
"""Extract the on-screen keyboard from the original iACE ViewController.xib.

Writes assets/keyboard_map.json: the keyboard photo's size and, for each key, its rectangle
in photo pixels, its matrix port and mask, and a label. In the xib, a key button's tag is
(mask << 8) | port and the photo sits at x = -6 in the keyboard view.
Also copies the keyboard photo to assets/images/.
"""
import json
import pathlib
import shutil
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "archive/iACE/iACE"
PHOTO_OFFSET_X = 6  # the photo's frame is x=-6 in the keyboard view

# Half-rows of the ACE keyboard matrix, bit 0 first.
MATRIX = [
    ["SHIFT", "SYMBOL SHIFT", "Z", "X", "C"],
    ["A", "S", "D", "F", "G"],
    ["Q", "W", "E", "R", "T"],
    ["1", "2", "3", "4", "5"],
    ["0", "9", "8", "7", "6"],
    ["P", "O", "I", "U", "Y"],
    ["ENTER", "L", "K", "J", "H"],
    ["SPACE", "M", "N", "B", "V"],
]

tree = ET.parse(SRC / "en.lproj/ViewController.xib")
keyboard = next(v for v in tree.iter("view") if v.get("userLabel") == "View (Keyboard)")
photo = next(i for i in keyboard.iter("imageView") if i.get("image") == "jupiterace.jpg")
photo_frame = photo.find("rect").attrib

keys = []
for button in keyboard.find("subviews").findall("button"):
    tag = button.get("tag")
    actions = {a.get("selector") for a in button.iter("action")}
    if tag is None or not actions & {"keyDown:", "shiftKeyDown:"}:
        continue
    tag = int(tag)
    port, mask = tag & 0xFF, tag >> 8
    bit = mask.bit_length() - 1
    assert mask == 1 << bit, f"one key per button, got tag {tag}"
    frame = button.find("rect").attrib
    keys.append({
        "label": MATRIX[port][bit],
        "port": port,
        "mask": mask,
        "shift": "shiftKeyDown:" in actions,
        "x": float(frame["x"]) + PHOTO_OFFSET_X,
        "y": float(frame["y"]),
        "width": float(frame["width"]),
        "height": float(frame["height"]),
    })

keys.sort(key=lambda k: (k["y"], k["x"]))
assert len(keys) == 40, len(keys)
assert len({(k["port"], k["mask"]) for k in keys}) == 40, "duplicate keys"

out = {
    "image": "assets/images/jupiterace.jpg",
    "imageWidth": float(photo_frame["width"]),
    "imageHeight": float(photo_frame["height"]),
    "keys": keys,
}
(ROOT / "assets/images/2.0x").mkdir(parents=True, exist_ok=True)
shutil.copy(SRC / "jupiterace.jpg", ROOT / "assets/images/jupiterace.jpg")
shutil.copy(SRC / "jupiterace@2x.jpg", ROOT / "assets/images/2.0x/jupiterace.jpg")
(ROOT / "assets/keyboard_map.json").write_text(json.dumps(out, indent=1) + "\n")
print(f"wrote assets/keyboard_map.json ({len(keys)} keys)")
