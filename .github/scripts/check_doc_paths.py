#!/usr/bin/env python3
"""Fail if a doc references a repo path (charts/, argocd/, platform/,
.github/) that doesn't exist. Only checks paths inside backtick spans or
fenced code blocks, and only paths whose first segment is one of those
known top-level directories — registry refs, hostnames, and container-
internal paths are left alone on purpose. Placeholder segments like
<service> or 0N are treated as wildcards.
"""
import glob
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
TARGET_FILES = ["README.md", "platform/README.md"]
KNOWN_TOP_LEVEL_DIRS = {"charts", "argocd", "platform", ".github"}

PATH_TOKEN_RE = re.compile(r"\.?/?(?:[A-Za-z0-9_.\-<>]+/)+[A-Za-z0-9_.\-<>*]+")
INLINE_CODE_RE = re.compile(r"`([^`]+)`")
PLACEHOLDER_RE = re.compile(r"<[^>]+>|\b[0-9]*N\b")


def candidate_paths_in_text(text):
    for m in INLINE_CODE_RE.finditer(text):
        span = m.group(1)
        for tok in PATH_TOKEN_RE.finditer(span):
            yield tok.group(0)


def to_glob_pattern(raw):
    raw = raw.lstrip("./")
    return PLACEHOLDER_RE.sub("*", raw)


def check_file(path):
    failures = []
    in_fence = False
    lines = path.read_text().splitlines()
    for lineno, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        candidates = set()
        if in_fence:
            for tok in PATH_TOKEN_RE.finditer(line):
                candidates.add(tok.group(0))
        else:
            candidates.update(candidate_paths_in_text(line))

        for raw in candidates:
            if "://" in raw:
                continue
            first_segment = raw.lstrip("./").split("/", 1)[0]
            if first_segment not in KNOWN_TOP_LEVEL_DIRS:
                continue
            pattern = to_glob_pattern(raw)
            if "*" in pattern:
                matches = glob.glob(str(REPO_ROOT / pattern))
            else:
                target = REPO_ROOT / pattern
                matches = [str(target)] if target.exists() else []
            if not matches:
                failures.append((path, lineno, raw))
    return failures


def main():
    all_failures = []
    for rel in TARGET_FILES:
        path = REPO_ROOT / rel
        if not path.exists():
            print(f"docs-check: target file {rel} does not exist", file=sys.stderr)
            all_failures.append((path, 0, "(missing target file itself)"))
            continue
        all_failures.extend(check_file(path))

    if all_failures:
        print("docs-check FAILED — doc references path(s) that don't exist:\n")
        for path, lineno, raw in all_failures:
            rel = path.relative_to(REPO_ROOT)
            print(f"  {rel}:{lineno}: `{raw}`")
        return 1

    print("docs-check OK — every checked path reference resolves.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
