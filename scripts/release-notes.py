#!/usr/bin/env python3
"""Validate release metadata and extract one changelog section."""

from __future__ import annotations

import argparse
from datetime import date
from pathlib import Path
import re


VERSION_RE = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")
VERSION_HEADING_RE = re.compile(r"^## \[([^]]+)] - ([0-9]{4}-[0-9]{2}-[0-9]{2})\s*$")
VERSION_HEADING_START_RE = re.compile(r"^## \[([^]]+)](?:\s|$)")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
ENTRY_RE = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*?)\s*$")


class ReleaseNotesError(ValueError):
    pass


def validate_version(version_text: str) -> str:
    version = version_text.strip()
    if not VERSION_RE.fullmatch(version):
        raise ReleaseNotesError(
            "VERSION must be a stable three-part version without leading zeros"
        )
    return version


def validate_tag(tag: str, version: str) -> None:
    if tag != f"v{version}":
        raise ReleaseNotesError(f"tag {tag!r} does not match VERSION {version!r}")


def _outside_fence_lines(text: str) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    fence_char = ""
    fence_length = 0
    for index, line in enumerate(text.splitlines(keepends=True)):
        match = FENCE_RE.match(line)
        if not fence_char:
            result.append((index, line))
            if match:
                fence_char = match.group(1)[0]
                fence_length = len(match.group(1))
        elif match and match.group(1)[0] == fence_char and len(match.group(1)) >= fence_length:
            fence_char = ""
            fence_length = 0
    return result


def _has_entry(body: str) -> bool:
    without_comments = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL)
    return any(
        match and match.group(1).strip()
        for _, line in _outside_fence_lines(without_comments)
        if (match := ENTRY_RE.match(line))
    )


def extract_release_notes(changelog: str, version: str) -> str:
    lines = changelog.splitlines(keepends=True)
    outside = _outside_fence_lines(changelog)
    matches: list[tuple[int, str]] = []

    for index, line in outside:
        heading = VERSION_HEADING_START_RE.match(line.rstrip("\r\n"))
        if heading and heading.group(1) == version:
            matches.append((index, line.rstrip("\r\n")))

    if not matches:
        raise ReleaseNotesError(f"CHANGELOG.md has no entry for {version}")
    if len(matches) != 1:
        raise ReleaseNotesError(f"CHANGELOG.md has duplicate entries for {version}")

    start, heading_text = matches[0]
    heading = VERSION_HEADING_RE.fullmatch(heading_text)
    if not heading:
        raise ReleaseNotesError(f"CHANGELOG.md has an invalid heading for {version}")
    try:
        date.fromisoformat(heading.group(2))
    except ValueError as error:
        raise ReleaseNotesError(f"CHANGELOG.md has an invalid date for {version}") from error

    end = len(lines)
    for index, line in outside:
        if index > start and re.match(r"^##(?:\s|$)", line):
            end = index
            break

    body = "".join(lines[start + 1 : end]).strip()
    if not _has_entry(body):
        raise ReleaseNotesError(f"CHANGELOG.md entry for {version} has no non-empty item")
    return body + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version-file", default=Path("VERSION"), type=Path)
    parser.add_argument("--changelog", default=Path("CHANGELOG.md"), type=Path)
    args = parser.parse_args()

    version = validate_version(args.version_file.read_text(encoding="utf-8"))
    validate_tag(args.tag, version)
    notes = extract_release_notes(args.changelog.read_text(encoding="utf-8"), version)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(notes, encoding="utf-8")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ReleaseNotesError) as error:
        raise SystemExit(f"release metadata error: {error}") from error
