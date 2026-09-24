#!/usr/bin/env python3
"""Convert the original iACE manual annotations (annotations.dic, an NSKeyedArchiver plist)
to assets/annotations.json, and copy the manual PDF to assets/manual.pdf.

In iACE 1.x a page view was 760 pt wide and showed the 612x792 pt PDF page scaled to its width,
top-left aligned, so view points / (760/612) are PDF points (top-left origin). Its pageNumber k
showed PDF page k-1 (1-based), and "goto N" went to pageNumber N+2, i.e. PDF page N+1.

Output: {"pageWidth", "pageHeight", "annotations": [{"page", "x", "y", "width", "height",
"action": "type" | "goto" | "open", "text" | "target" | "url"}]} with pages 1-based.
"""
import json
import pathlib
import plistlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "archive/iACE/iACE"
VIEW_WIDTH = 760.0
PAGE_WIDTH, PAGE_HEIGHT = 612.0, 792.0
SCALE = VIEW_WIDTH / PAGE_WIDTH
TYPE_BUTTON = (70.0, 44.0)  # iACE 1.x drew every "type" annotation at this size

archive = plistlib.load(open(SRC / "annotations.dic", "rb"))
objects = archive["$objects"]


def resolve(x):
    return objects[x.data] if isinstance(x, plistlib.UID) else x


pages = resolve(archive["$top"]["annotations"])
out = []
for key, value in zip(pages["NS.keys"], pages["NS.objects"]):
    page_number = resolve(key)
    for item in resolve(value)["NS.objects"]:
        item = resolve(item)
        x, y, w, h = map(float, re.findall(r"-?[\d.]+", resolve(item["rect"])))
        text = resolve(item["value"])
        action, _, arg = text.partition(" ")
        entry = {"page": page_number - 1}
        if action == "type":
            w, h = TYPE_BUTTON
            lines = arg.replace("\\", "\n").rstrip("\n")
            entry.update(action="type", text=lines + "\n")
        elif action == "goto":
            entry.update(action="goto", target=int(arg) + 1)
        elif action == "open":
            entry.update(action="open", url=arg)
        else:
            raise SystemExit(f"unknown annotation {text!r}")
        entry.update(
            x=round(x / SCALE, 2),
            y=round(y / SCALE, 2),
            width=round(w / SCALE, 2),
            height=round(h / SCALE, 2),
        )
        out.append(entry)

out.sort(key=lambda a: (a["page"], a["y"], a["x"]))
assert len(out) == 104, len(out)
assert all(0 <= a["x"] and a["x"] + a["width"] <= PAGE_WIDTH + 1 for a in out)
(ROOT / "assets/annotations.json").write_text(
    json.dumps({"pageWidth": PAGE_WIDTH, "pageHeight": PAGE_HEIGHT, "annotations": out}, indent=1) + "\n"
)
shutil.copy(SRC / "JA-Manual-Second-Edition.pdf", ROOT / "assets/manual.pdf")
counts = {k: sum(a["action"] == k for a in out) for k in ("type", "goto", "open")}
print(f"wrote assets/annotations.json ({len(out)} annotations: {counts}) and assets/manual.pdf")
