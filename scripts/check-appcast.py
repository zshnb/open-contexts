#!/usr/bin/env python3
"""Fail a release if its Sparkle feed does not describe the uploaded DMG."""

import base64
import binascii
import pathlib
import sys
import xml.etree.ElementTree as ET


def check(appcast, dmg, release_notes, repository, tag, version, build):
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    root = ET.parse(appcast).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Appcast must contain exactly one release")
    item = items[0]
    if release_notes.name != dmg.with_suffix(".md").name or not release_notes.read_text(encoding="utf-8").strip():
        raise ValueError("Release notes must be non-empty Markdown matching the DMG name")
    notes_link = item.find(f"{sparkle}releaseNotesLink")
    expected_notes_url = f"https://github.com/{repository}/releases/download/{tag}/{release_notes.name}"
    if notes_link is None or (notes_link.text or "").strip() != expected_notes_url:
        raise ValueError("Appcast has an unexpected release notes URL")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Appcast is missing an enclosure")
    expected_url = f"https://github.com/{repository}/releases/download/{tag}/{dmg.name}"
    expected = {
        "url": expected_url,
        "length": str(dmg.stat().st_size),
    }
    for key, value in expected.items():
        if enclosure.get(key) != value:
            raise ValueError(f"Appcast enclosure has unexpected {key}")
    for key, value in (("version", build), ("shortVersionString", version)):
        if (item.findtext(f"{sparkle}{key}") or enclosure.get(f"{sparkle}{key}")) != value:
            raise ValueError(f"Appcast has unexpected sparkle:{key}")
    signature = enclosure.get(f"{sparkle}edSignature", "")
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except binascii.Error as error:
        raise ValueError("Appcast has an invalid EdDSA signature") from error
    if len(signature_bytes) != 64:
        raise ValueError("Appcast has no Ed25519 signature")
    return signature


if __name__ == "__main__":
    if len(sys.argv) != 8:
        raise SystemExit("usage: check-appcast.py APPCAST DMG RELEASE_NOTES REPOSITORY TAG VERSION BUILD")
    try:
        print(check(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), *sys.argv[4:]))
    except (OSError, ET.ParseError, ValueError) as error:
        raise SystemExit(f"Invalid Sparkle appcast: {error}") from error
