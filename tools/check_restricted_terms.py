#!/usr/bin/env python3
"""Reject restricted vocabulary in tracked content and commit messages."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

_RULES = tuple(bytes(v) for v in (
    (99, 111, 100, 101, 120),
    (99, 104, 97, 116, 103, 112, 116),
    (111, 112, 101, 110, 97, 105),
    (99, 108, 97, 117, 100, 101),
    (97, 110, 116, 104, 114, 111, 112, 105, 99),
    (97, 105),
    (108, 108, 109),
    (108, 109),
    (109, 108),
    (83, 80, 68, 88),
))

_PATTERNS = tuple(
    (n, re.compile(rb"(?<![A-Za-z0-9_])" + re.escape(token) + rb"(?![A-Za-z0-9_])", re.I))
    for n, token in enumerate(_RULES, 1)
)


def run_git(*args: str) -> bytes:
    return subprocess.check_output(("git", *args), cwd=ROOT)


def index_entries():
    raw = run_git("ls-files", "--stage", "-z")
    for record in raw.split(b"\0"):
        if not record:
            continue
        header, path = record.split(b"\t", 1)
        mode, sha, stage = header.split()
        if stage == b"0":
            yield path, sha.decode("ascii")


def tree_entries():
    raw = run_git("ls-tree", "-r", "-z", "HEAD")
    for record in raw.split(b"\0"):
        if not record:
            continue
        header, path = record.split(b"\t", 1)
        mode, kind, sha = header.split()
        if kind == b"blob":
            yield path, sha.decode("ascii")


def blob(sha: str) -> bytes:
    return run_git("cat-file", "blob", sha)


def scan_bytes(label: bytes, data: bytes) -> int:
    failures = 0
    for number, pattern in _PATTERNS:
        for match in pattern.finditer(data):
            line = data.count(b"\n", 0, match.start()) + 1
            where = label.decode("utf-8", "backslashreplace")
            print(f"{where}:{line}: restricted token #{number}", file=sys.stderr)
            failures += 1
    return failures


def scan_entry(path: bytes, sha: str) -> int:
    failures = scan_bytes(b"<path>", path)
    failures += scan_bytes(path, blob(sha))
    return failures


def scan_index() -> int:
    return sum(scan_entry(path, sha) for path, sha in index_entries())


def scan_tree() -> int:
    return sum(scan_entry(path, sha) for path, sha in tree_entries())


def scan_message_file(path: str) -> int:
    return scan_bytes(b"<commit-message>", Path(path).read_bytes())


def scan_head_message() -> int:
    return scan_bytes(b"<commit-message>", run_git("log", "-1", "--format=%B"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--index", action="store_true")
    ap.add_argument("--tree", action="store_true")
    ap.add_argument("--message-file")
    ap.add_argument("--head-message", action="store_true")
    args = ap.parse_args()

    if not (args.index or args.tree or args.message_file or args.head_message):
        ap.error("choose at least one check mode")

    failures = 0
    if args.index:
        failures += scan_index()
    if args.tree:
        failures += scan_tree()
    if args.message_file:
        failures += scan_message_file(args.message_file)
    if args.head_message:
        failures += scan_head_message()

    if failures:
        print(f"repository vocabulary gate rejected {failures} occurrence(s)", file=sys.stderr)
        return 1

    print("repository vocabulary gate: clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
