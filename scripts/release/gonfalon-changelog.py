#!/usr/bin/env python3
"""Record a release in gonfalon's apidocs/CHANGELOG.md.

Usage: gonfalon-changelog.py CHANGELOG VERSION DATE NOTES [WARNINGS]

Moves the entries listed in NOTES (the release notes, in the same `### `
heading / `- ` bullet form) out of `## [Unreleased]` into a new
`## [VERSION] - DATE` section below it. Entries under [Unreleased] that are not
in NOTES stay there: they were merged after the gonfalon commit the release
shipped, so they are not released yet.

An entry is matched by its exact text, the way release-notes.py produced it. A
released entry that is no longer under [Unreleased] (edited or moved since) is
still written to the new section, and listed in WARNINGS (default stderr) so
the PR can say so. Errors always go to stderr, so a failure shows in the log.
"""

import sys


def parse_entries(lines):
    """[(heading, entry_text)] for each top-level bullet, in order."""
    entries, heading, current = [], None, None
    for line in lines:
        if line.startswith("### "):
            heading, current = line[4:].strip(), None
        elif line.startswith("- "):
            current = [line]
            entries.append((heading, current))
        elif current is not None and line.strip():
            current.append(line)
    return [(h, "\n".join(ls)) for h, ls in entries]


def render(entries):
    out, last = [], object()
    for heading, text in entries:
        if heading != last:
            if out:
                out.append("")
            out += [f"### {heading}", ""]
            last = heading
        out.append(text)
    return out


def main(argv):
    if len(argv) not in (4, 5):
        sys.exit(__doc__)
    path, version, date, notes_path = argv[:4]
    warnings = open(argv[4], "w") if len(argv) == 5 else sys.stderr
    lines = open(path).read().split("\n")
    if any(l.startswith(f"## [{version}]") for l in lines):
        sys.exit(f"{path} already has a '## [{version}]' section; this release is already recorded")

    try:
        start = lines.index("## [Unreleased]")
    except ValueError:
        sys.exit(f"no '## [Unreleased]' heading in {path}")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))

    released = parse_entries(open(notes_path).read().split("\n"))
    if not released:
        # A release with no changelog entries (descriptions only, say) leaves
        # nothing to move. Change nothing, so pr-downstream opens no PR.
        print(f"no entries in {notes_path}; leaving {path} unchanged", file=sys.stderr)
        return
    released_texts = {text for _, text in released}
    unreleased = parse_entries(lines[start + 1:end])
    remaining = [(h, t) for h, t in unreleased if t not in released_texts]

    missing = released_texts - {t for _, t in unreleased}
    for text in sorted(missing):
        print(f"not under [Unreleased] any more, recorded anyway: {text.splitlines()[0][:120]}", file=warnings)

    section = ["## [Unreleased]", ""]
    if remaining:
        section += render(remaining) + [""]
    section += [f"## [{version}] - {date}", ""] + render(released) + [""]
    with open(path, "w") as f:
        f.write("\n".join(lines[:start] + section + lines[end:]))


if __name__ == "__main__":
    main(sys.argv[1:])
