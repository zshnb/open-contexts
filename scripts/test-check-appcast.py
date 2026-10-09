#!/usr/bin/env python3

import base64
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("check_appcast", Path(__file__).with_name("check-appcast.py"))
check_appcast = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(check_appcast)
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class AppcastTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.dmg = self.directory / "OpenContexts-1.2.3-universal.dmg"
        self.dmg.write_bytes(b"fixture")
        self.notes = self.dmg.with_suffix(".md")
        self.notes.write_text("### Fixed\n- Fix switching.\n\n### 修复\n- 修复切换。\n", encoding="utf-8")
        self.appcast = self.directory / "appcast.xml"
        self.root = ET.Element("rss")
        self.item = ET.SubElement(ET.SubElement(self.root, "channel"), "item")
        ET.SubElement(self.item, SPARKLE + "version").text = "42"
        ET.SubElement(self.item, SPARKLE + "shortVersionString").text = "1.2.3"
        self.link = ET.SubElement(self.item, SPARKLE + "releaseNotesLink")
        self.link.text = "https://github.com/zshnb/open-contexts/releases/download/v1.2.3/" + self.notes.name
        self.signature = base64.b64encode(bytes(64)).decode()
        self.enclosure = ET.SubElement(self.item, "enclosure", {
            "url": "https://github.com/zshnb/open-contexts/releases/download/v1.2.3/" + self.dmg.name,
            "length": "7", SPARKLE + "edSignature": self.signature,
        })

    def check(self):
        ET.ElementTree(self.root).write(self.appcast, encoding="utf-8")
        return check_appcast.check(self.appcast, self.dmg, self.notes, "zshnb/open-contexts", "v1.2.3", "1.2.3", "42")

    def test_accepts_matching_markdown_notes(self):
        self.assertEqual(self.check(), self.signature)

    def test_rejects_missing_link_wrong_release_and_wrong_extension(self):
        original_url = self.link.text
        for url in (None, original_url.replace("v1.2.3/", "v1.2.2/"), original_url.removesuffix(".md") + ".html"):
            with self.subTest(url=url):
                self.link.text = url
                with self.assertRaisesRegex(ValueError, "release notes URL"):
                    self.check()
        self.link.text = original_url
        self.item.remove(self.link)
        with self.assertRaisesRegex(ValueError, "release notes URL"):
            self.check()

    def test_rejects_missing_empty_and_wrong_filename_notes(self):
        self.notes.unlink()
        with self.assertRaises(FileNotFoundError):
            self.check()
        self.notes.write_text(" \n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "non-empty Markdown"):
            self.check()
        self.notes = self.directory / "release-notes.md"
        self.notes.write_text("- valid content\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "matching the DMG name"):
            self.check()

    def test_preserves_archive_and_signature_validation(self):
        self.enclosure.set("length", "8")
        with self.assertRaisesRegex(ValueError, "unexpected length"):
            self.check()
        self.enclosure.set("length", "7")
        self.enclosure.set(SPARKLE + "edSignature", base64.b64encode(bytes(32)).decode())
        with self.assertRaisesRegex(ValueError, "Ed25519 signature"):
            self.check()


if __name__ == "__main__":
    unittest.main()
