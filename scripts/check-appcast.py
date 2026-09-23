#!/usr/bin/env python3
"""Fail a release if its Sparkle feed does not describe the uploaded DMG."""

import base64
import binascii
import pathlib
import sys
import xml.etree.ElementTree as ET


def check(appcast, dmg, repository, tag, version, build):
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    root = ET.parse(appcast).getroot()
    items = root.findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Appcast must contain exactly one release")
    item = items[0]
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
    if len(sys.argv) != 7:
        raise SystemExit("usage: check-appcast.py APPCAST DMG REPOSITORY TAG VERSION BUILD")
    try:
        print(check(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), *sys.argv[3:]))
    except (OSError, ET.ParseError, ValueError) as error:
        raise SystemExit(f"Invalid Sparkle appcast: {error}") from error
