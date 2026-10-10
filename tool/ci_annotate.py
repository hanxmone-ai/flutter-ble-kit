"""Turns CI output into GitHub annotations, which stay readable through the checks API.

Usage: python3 tool/ci_annotate.py LEVEL FILE [FILE...]   (LEVEL: error, warning or notice)

A `.jsonl` file is read as `flutter test --machine` output and reduced to the failing tests with
their errors; any other file contributes its last lines.
"""

import json
import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MAX_LINES = 120
MAX_CHARS = 6000


def failures(path: Path) -> list[str]:
    names: dict[int, str] = {}
    errors: dict[int, list[str]] = {}
    failed: list[int] = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, list):
            continue
        kind = event.get("type")
        if kind == "testStart":
            names[event["test"]["id"]] = event["test"]["name"]
        elif kind == "error":
            errors.setdefault(event["testID"], []).append(f"{event['error']}\n{event.get('stackTrace', '')}")
        elif kind == "print":
            # Flutter reports exceptions caught during a widget test as printed text.
            errors.setdefault(event["testID"], []).append(event.get("message", ""))
        elif kind == "testDone" and event.get("result") != "success" and not event.get("hidden"):
            failed.append(event["testID"])
    reports = []
    for test_id in failed:
        detail = "\n".join(errors.get(test_id, ["(no error message)"]))
        reports.append(f"FAILED: {names.get(test_id, test_id)}\n{detail}")
    return reports


def tail(path: Path) -> list[str]:
    lines = ANSI.sub("", path.read_text(errors="replace")).splitlines()
    lines = [line for line in lines if not line.startswith(("✅", "::"))]
    return ["\n".join(lines[-MAX_LINES:])]


def escape(text: str) -> str:
    text = text.replace("::", ": :")[:MAX_CHARS]
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


level, *files = sys.argv[1:]
for name in files:
    path = Path(name)
    if not path.exists():
        continue
    parts = failures(path) if path.suffix == ".jsonl" else tail(path)
    for index, part in enumerate(parts):
        print(f"::{level} title={path.name} #{index + 1}::{escape(part)}")
