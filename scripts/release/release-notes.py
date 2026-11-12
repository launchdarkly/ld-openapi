#!/usr/bin/env python3
"""Release notes: gonfalon changelog entries added since the last release.

Usage: release-notes.py CHANGELOG_NOW [CHANGELOG_AT_LAST_RELEASE]

Prints the entries under `## [Unreleased]` in CHANGELOG_NOW that were not
already under `## [Unreleased]` in CHANGELOG_AT_LAST_RELEASE, grouped by their
`### ` heading. With no second file, prints all of [Unreleased].

Diffing two gonfalon commits, rather than reading [Unreleased] alone, keeps the
notes right whether or not gonfalon's release PR (which renames [Unreleased]
to the released version) has merged yet.
"""

import sys


def unreleased_entries(path):
    """[(heading, entry_text)] for each top-level bullet under [Unreleased]."""
    entries, heading, current, capturing = [], None, None, False
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("## "):
                if capturing:
                    break
                capturing = line.strip() == "## [Unreleased]"
                continue
            if not capturing:
                continue
            if line.startswith("### "):
                heading, current = line[4:].strip(), None
            elif line.startswith("- "):
                current = [line]
                entries.append((heading, current))
            elif current is not None and line.strip():
                current.append(line)  # continuation of the entry above
    return [(h, "\n".join(lines)) for h, lines in entries]


def main(argv):
    if not 1 <= len(argv) <= 2:
        sys.exit(__doc__)
    now = unreleased_entries(argv[0])
    released = set()
    if len(argv) == 2:
        released = {text for _, text in unreleased_entries(argv[1])}
    sections = {}
    for heading, text in now:
        if text not in released:
            sections.setdefault(heading, []).append(text)
    out = []
    for heading, texts in sections.items():
        out.append(f"### {heading}\n")
        out.extend(texts)
        out.append("")
    print("\n".join(out).strip())


if __name__ == "__main__":
    main(sys.argv[1:])
