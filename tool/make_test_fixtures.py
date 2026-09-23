#!/usr/bin/env python3
"""Writes the plist fixtures used by the Dart tests (test/fixtures/). Run by hand when they change."""
import pathlib
import plistlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIX = ROOT / "test/fixtures"

sample = {
    "name": "ACE",
    "count": 42,
    "big": 2**40,
    "negative": -5,
    "ratio": 1.5,
    "on": True,
    "off": False,
    "blob": bytes([0, 1, 255]),
    "list": [1, "two", [3]],
    "unicode": "Jüpiter © ACE",
    "nested": {"a": 1},
}
(FIX / "plist").mkdir(parents=True, exist_ok=True)
(FIX / "plist/sample.xml.plist").write_bytes(plistlib.dumps(sample, fmt=plistlib.FMT_XML))
(FIX / "plist/sample.binary.plist").write_bytes(plistlib.dumps(sample, fmt=plistlib.FMT_BINARY))

# NSUserDefaults of iACE 1.2 (binary, as iOS writes it), with unrelated keys too.
prefs = {
    "lastpage": 57,
    "toggle_shift_keys": True,
    "reset_msg2": True,
    "NSLanguages": ["en"],
}
(FIX / "legacy").mkdir(parents=True, exist_ok=True)
(FIX / "legacy/com.memention.iACE.plist").write_bytes(plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY))
print("wrote test fixtures")
