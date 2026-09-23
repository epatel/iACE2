#!/usr/bin/env python3
"""Extract the bundled Frogger tape from the original iACE frogger.h into assets/tapes/frogger.dic.

The tape is stored as blocks of [u16 little-endian length][length bytes], header block then data block.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
src = (ROOT / "archive/iACE/iACE/frogger.h").read_text()
body, length = re.search(r"\{(.*?)\};\s*unsigned int FROGGER_DIC_len = (\d+);", src, re.S).groups()
data = bytes(int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{2})", body))
assert len(data) == int(length), (len(data), length)
out = ROOT / "assets/tapes/frogger.dic"
out.write_bytes(data)
print(f"wrote {out.relative_to(ROOT)} ({len(data)} bytes)")
