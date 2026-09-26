#!/usr/bin/env python3
"""Fail if a values file actually read by a LIVE ArgoCD Application still
contains a REPLACE_ME placeholder.

"Live" means: an Application manifest under argocd/azure/bootstrap/ — the
only directory any real ArgoCD install reads today (see root README.md's
repo-layout section). argocd/azure-prod/ (no cluster yet) and
argocd/_aws-disabled/ (parked) are dormant by the repo's own convention
and are deliberately NOT checked here — REPLACE_ME there is expected and
fine. If azure-prod/ ever becomes live, add its bootstrap dir to
LIVE_BOOTSTRAP_DIRS below.
"""
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
LIVE_BOOTSTRAP_DIRS = ["argocd/azure/bootstrap"]

PATH_RE = re.compile(r"^\s*path:\s*(\S+)\s*$", re.MULTILINE)
VALUEFILES_BLOCK_RE = re.compile(r"valueFiles:\s*\n((?:\s*-\s*\S+\s*\n?)+)")
VALUEFILE_ITEM_RE = re.compile(r"-\s*(\S+)")
PLACEHOLDER = "REPLACE_ME"


def referenced_values_files(app_yaml_text):
    # Multi-source Applications (spec.sources:, e.g. 05-monitoring.yaml)
    # have a different shape — several path/valueFiles pairs, one per
    # source, with $values refs. This script only understands the
    # single-source spec.source: shape every per-service Application
    # uses. Multi-source Applications are skipped rather than misparsed;
    # today none of their values files contain REPLACE_ME (they're
    # platform/ reference data, not per-environment overrides).
    if re.search(r"^\s*sources:\s*$", app_yaml_text, re.MULTILINE):
        return []
    path_match = PATH_RE.search(app_yaml_text)
    block_match = VALUEFILES_BLOCK_RE.search(app_yaml_text)
    if not path_match or not block_match:
        return []
    chart_path = path_match.group(1)
    return [
        f"{chart_path}/{m.group(1)}"
        for m in VALUEFILE_ITEM_RE.finditer(block_match.group(1))
    ]


def main():
    failures = []
    checked = []

    for bootstrap_dir in LIVE_BOOTSTRAP_DIRS:
        d = REPO_ROOT / bootstrap_dir
        if not d.is_dir():
            print(f"check-prod-placeholders: {bootstrap_dir} does not exist", file=sys.stderr)
            return 1
        for app_file in sorted(d.glob("*.yaml")):
            text = app_file.read_text()
            for rel_values_path in referenced_values_files(text):
                values_path = REPO_ROOT / rel_values_path
                checked.append(str(values_path.relative_to(REPO_ROOT)))
                if not values_path.exists():
                    failures.append((app_file, rel_values_path, "referenced file does not exist"))
                    continue
                if PLACEHOLDER in values_path.read_text():
                    failures.append((app_file, rel_values_path, f"contains {PLACEHOLDER}"))

    if failures:
        print("check-prod-placeholders FAILED — a LIVE Application references an unready values file:\n")
        for app_file, rel_values_path, reason in failures:
            print(f"  {app_file.relative_to(REPO_ROOT)} -> {rel_values_path}: {reason}")
        return 1

    print(f"check-prod-placeholders OK — {len(checked)} values file(s) read by live Applications, no {PLACEHOLDER} found.")
    for c in checked:
        print(f"  checked: {c}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
