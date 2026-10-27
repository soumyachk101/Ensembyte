#!/usr/bin/env python3
"""Builds website/changelog.json from CHANGELOG.md for macOS releases.

Run: python3 scripts/build_changelog.py
Idempotent: rewrites website/changelog.json from scratch each run.
Ensures macOS changelog feeds contain only macOS/Swift changes.
"""

import datetime
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHANGELOG = (ROOT / "CHANGELOG.md") if (ROOT / "CHANGELOG.md").exists() else (ROOT.parent / "CHANGELOG.md")
OUT = (ROOT.parent / "website" / "changelog.json") if (ROOT.parent / "website").exists() else (ROOT / "website" / "changelog.json")

RELEASE_RE = re.compile(r"^## \[(\d+(?:\.\d+)*)\](?: - (\d{4}-\d{2}-\d{2}))?\s*$")
SECTION_RE = re.compile(r"^### (.*)$")

HEADING_MAP = {
    "new features": "New features",
    "added": "New features",
    "bug fixes": "Bug fixes",
    "fixed": "Bug fixes",
    "refinements": "Refinements",
    "macos updates (`ensembyte-swift/`)": "macOS Updates",
    "macos updates": "macOS Updates",
    "swift core updates": "macOS Updates",
    "swift core improvements & testing": "macOS Updates",
}
SECTION_ORDER = ["New features", "macOS Updates", "Bug fixes", "Refinements"]


def git_date(args):
    try:
        out = subprocess.run(
            ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
        )
        return out.stdout.strip() or None
    except Exception:
        return None


def release_date(version, heading_date=None):
    if heading_date:
        return heading_date
    date = git_date(["log", "-1", "--format=%cs", f"v{version}"])
    if date:
        return date
    date = git_date(["log", "-1", "--format=%cs", "--", "CHANGELOG.md"])
    if date:
        return date
    return datetime.date.today().isoformat()


def strip_emphasis(text):
    return text.replace("**", "").replace("__", "").replace("*", "").replace("_", "")


def split_releases(text):
    releases = []
    current = None
    for line in text.splitlines():
        m = RELEASE_RE.match(line)
        if m:
            if current is not None:
                releases.append(current)
            current = {"version": m.group(1), "date": m.group(2), "lines": []}
            continue
        if current is not None:
            current["lines"].append(line)
    if current is not None:
        releases.append(current)
    return releases


def clean_summary_for_mac(summary_text):
    # Filter out sentences or clauses mentioning Ensembyte-rust or Windows/Linux
    if not summary_text:
        return ""
    # Split by comma or semicolon followed by 'alongside' or 'in Ensembyte-rust'
    cleaned = re.sub(r',?\s*alongside\s+[^.]*?(?:Ensembyte-rust|Windows and Linux)[^.]*?\.', '.', summary_text, flags=re.IGNORECASE)
    cleaned = re.sub(r',?\s*and automated CI cargo-deny[^.]*?\.', '.', cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r'\s*\([^)]*Ensembyte-rust[^)]*\)', '', cleaned)
    return cleaned.strip()


def parse_notes(lines):
    summary_lines = []
    sections = {}
    thanks = []
    current = None
    for line in lines:
        m = SECTION_RE.match(line)
        if m:
            heading = m.group(1).strip()
            key = heading.lower()
            if key == "thanks":
                current = "thanks"
                continue
            # Filter out Rust / cross-platform headings for macOS release notes
            if "ensembyte-rust" in key or "security & engine" in key or "cross-platform" in key:
                current = "skip_platform"
                continue
            current = HEADING_MAP.get(key)
            if current and current not in sections:
                sections[current] = []
            elif current is None:
                current = None
            continue
        if current == "skip_platform":
            continue
        if current is None:
            if line.strip():
                summary_lines.append(line.strip())
        else:
            m2 = re.match(r"^\s*-\s+(.*)$", line)
            if m2:
                item = strip_emphasis(m2.group(1).strip())
                if item:
                    if current == "thanks":
                        thanks.append(item)
                    else:
                        sections[current].append(item)
    summary = clean_summary_for_mac(" ".join(summary_lines))
    ordered = [
        {"title": title, "items": sections[title]}
        for title in SECTION_ORDER
        if title in sections and sections[title]
    ]
    return summary, ordered, thanks


def extract_section(version):
    text = CHANGELOG.read_text(encoding="utf-8")
    releases = split_releases(text)
    for rel in releases:
        if rel["version"] == version:
            lines = list(rel["lines"])
            while lines and not lines[0].strip():
                lines.pop(0)
            while lines and not lines[-1].strip():
                lines.pop()
            out = []
            skip = False
            for line in lines:
                if line.startswith("### "):
                    h = line[4:].strip().lower()
                    if "ensembyte-rust" in h or "security & engine" in h:
                        skip = True
                        continue
                    else:
                        skip = False
                        out.append("## " + line[4:])
                elif not skip:
                    out.append(line)
            return "\n".join(out) + "\n"
    return None


def version_key(version):
    nums = re.findall(r"\d+", version)
    return tuple(int(n) for n in nums)


def build_releases():
    text = CHANGELOG.read_text(encoding="utf-8")
    releases = []
    for rel in split_releases(text):
        version = rel["version"]
        summary, sections, thanks = parse_notes(rel["lines"])
        releases.append(
            {
                "version": version,
                "date": release_date(version, rel["date"]),
                "platform": "mac",
                "summary": summary,
                "sections": sections,
                "thanks": thanks,
            }
        )
    releases.sort(key=lambda r: version_key(r["version"]), reverse=True)
    return releases


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--section":
        version = sys.argv[2]
        section = extract_section(version)
        if section is None:
            print(f"No ## [{version}] section in CHANGELOG.md", file=sys.stderr)
            return 1
        sys.stdout.write(section)
        return 0
    releases = build_releases()
    payload = {
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "releases": releases,
    }
    OUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {len(releases)} releases to {OUT}")


if __name__ == "__main__":
    sys.exit(main())
