#!/usr/bin/env python3

import base64
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
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

    def test_generation_step_exports_notes_for_later_steps(self):
        repository = Path(__file__).resolve().parents[1]
        workflow = (repository / ".github/workflows/release.yml").read_text()
        step = workflow.split("      - name: Generate signed Sparkle appcast\n", 1)[1].split("      - name:", 1)[0]
        script = textwrap.dedent(step.split("        run: |\n", 1)[1])
        scripts = self.directory / "scripts"
        scripts.mkdir()
        shutil.copy2(repository / "scripts/check-appcast.py", scripts)
        dist = self.directory / "dist"
        dist.mkdir()
        shutil.copy2(self.notes, dist / "release-notes.md")
        ET.ElementTree(self.root).write(self.directory / "fixture-appcast.xml", encoding="utf-8")
        tools = self.directory / ".build/artifacts/tools"
        tools.mkdir(parents=True)
        # Stub key/signing tools; execute the real workflow shell and appcast checker.
        for name, body in {
            "swift": "cat >/dev/null",
            "plutil": "echo 42",
            "generate_appcast": "cat >/dev/null\ncp fixture-appcast.xml dist/sparkle/appcast.xml",
            "sign_update": "cat >/dev/null",
        }.items():
            executable = tools / name
            executable.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
            executable.chmod(0o755)
        exported = self.directory / "github-env"
        environment = {
            **os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "GITHUB_ENV": str(exported), "GITHUB_REPOSITORY": "zshnb/open-contexts",
            "RELEASE_TAG": "v1.2.3", "APP_VERSION": "1.2.3",
            "APP_PATH": "dist/OpenContexts.app", "DMG_PATH": str(self.dmg),
            "SPARKLE_ED_PRIVATE_KEY": "fixture-only",
        }
        environment.pop("SPARKLE_RELEASE_NOTES_PATH", None)
        result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script],
                                cwd=self.directory, env=environment, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = "dist/sparkle/" + self.notes.name
        self.assertEqual(exported.read_text(), "SPARKLE_RELEASE_NOTES_PATH=" + expected + "\n")
        self.assertEqual((self.directory / expected).read_bytes(), self.notes.read_bytes())


if __name__ == "__main__":
    unittest.main()
