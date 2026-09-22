#!/usr/bin/env python3

import importlib.util
from pathlib import Path
import sys
import unittest


SCRIPT = Path(__file__).with_name("release-notes.py")
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("release_notes", SCRIPT)
release_notes = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(release_notes)


class ReleaseNotesTests(unittest.TestCase):
    def test_extracts_target_and_ignores_headings_in_fences(self):
        changelog = """# Changelog

## [Unreleased]

- later

## [0.2.0] - 2026-09-22

### 新增
- current

```markdown
## [0.1.0] - 2026-01-01
```

- after fence

## [0.1.0] - 2026-01-01

- old
"""
        self.assertEqual(
            release_notes.extract_release_notes(changelog, "0.2.0"),
            "### 新增\n- current\n\n```markdown\n## [0.1.0] - 2026-01-01\n```\n\n- after fence\n",
        )

    def test_rejects_missing_duplicate_empty_and_invalid_date(self):
        invalid = (
            ("## [1.0.0] - 2026-01-01\n- item\n", "2.0.0"),
            ("## [1.0.0] - 2026-01-01\n- a\n## [1.0.0] - 2026-01-02\n- b\n", "1.0.0"),
            ("## [1.0.0] - bad\n- a\n## [1.0.0] - 2026-01-02\n- b\n", "1.0.0"),
            ("## [1.0.0] - 2026-01-01\n### 新增\n<!-- later -->\n-   \n", "1.0.0"),
            ("## [1.0.0] - 2026-01-01\n```text\n- not an entry\n```\n", "1.0.0"),
            ("## [1.0.0] - 2026-02-30\n- item\n", "1.0.0"),
        )
        for changelog, version in invalid:
            with self.subTest(changelog=changelog):
                with self.assertRaises(release_notes.ReleaseNotesError):
                    release_notes.extract_release_notes(changelog, version)

    def test_validates_version_and_matching_tag(self):
        self.assertEqual(release_notes.validate_version("1.2.3\n"), "1.2.3")
        for version in ("v1.2.3", "1.02.3", "1.2", "1.2.3-beta"):
            with self.assertRaises(release_notes.ReleaseNotesError):
                release_notes.validate_version(version)
        with self.assertRaises(release_notes.ReleaseNotesError):
            release_notes.validate_tag("1.2.3", "1.2.3")
        with self.assertRaises(release_notes.ReleaseNotesError):
            release_notes.validate_tag("v1.2.4", "1.2.3")


if __name__ == "__main__":
    unittest.main()
