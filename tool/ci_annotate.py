"""Turns analyzer, test and build output into GitHub Actions annotations.

Annotations show up on the run page and through the checks API, which makes
failures readable without downloading logs.

  python3 tool/ci_annotate.py analyze analyze.txt   # dart analyze --format=machine
  python3 tool/ci_annotate.py tests test.json       # flutter test --machine
  python3 tool/ci_annotate.py log build.log TITLE   # tail of any log
"""

import json
import os
import sys

ROOT = os.getcwd()


def esc(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "").replace("\n", "%0A")


def prop(text: str) -> str:
    return esc(text).replace(":", "%3A").replace(",", "%2C")


def rel(path: str) -> str:
    if path.startswith("file://"):
        path = path[7:]
    return os.path.relpath(path, ROOT) if path.startswith("/") else path


def analyze(path: str) -> int:
    failures = 0
    lines = [l for l in open(path, encoding="utf-8", errors="replace").read().splitlines() if l.count("|") >= 7]
    for line in lines:
        severity, _type, code, file, row, col, _length, message = line.split("|", 7)
        level = {"ERROR": "error", "WARNING": "warning"}.get(severity, "notice")
        if level != "notice":
            failures += 1
        print(f"::{level} file={rel(file)},line={row},col={col},title={code}::{esc(message)}")
    if lines:
        summary = "\n".join(l.split("|", 7)[3].split("/")[-1] + ":" + l.split("|")[4] + " " + l.split("|", 7)[7] for l in lines)
        print(f"::{'error' if failures else 'notice'} title=analyzer ({len(lines)} issues)::{esc(summary)}")
    return 1 if failures else 0


def tests(path: str) -> int:
    names, errors, failed = {}, {}, []
    suites = {}
    for raw in open(path, encoding="utf-8", errors="replace"):
        raw = raw.strip()
        if not raw.startswith("{"):
            continue
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "suite":
            suites[event["suite"]["id"]] = event["suite"].get("path", "")
        elif kind == "testStart":
            t = event["test"]
            names[t["id"]] = (t["name"], suites.get(t.get("suiteID"), ""), t.get("line"))
        elif kind == "error":
            errors.setdefault(event["testID"], []).append(
                event.get("error", "") + "\n" + "\n".join(event.get("stackTrace", "").splitlines()[:12])
            )
        elif kind == "testDone" and event.get("result") != "success":
            # Includes hidden "loading" tests, which carry compile errors.
            failed.append(event["testID"])
    for test_id in dict.fromkeys(failed):
        name, suite, line = names.get(test_id, ("unknown test", "", None))
        detail = "\n---\n".join(errors.get(test_id, ["(no error message)"]))[:6000]
        where = f"file={rel(suite)},line={line or 1}," if suite else ""
        print(f"::error {where}title={prop(name)[:200]}::{esc(detail)}")
    return 1 if failed else 0


def log(path: str, title: str) -> int:
    text = open(path, encoding="utf-8", errors="replace").read()
    interesting = [l for l in text.splitlines() if any(k in l for k in ("error", "Error", "FAILURE", "What went wrong", "e: ", "Exception"))]
    tail = "\n".join(text.splitlines()[-60:])
    body = "\n".join(interesting[:60]) + "\n=== tail ===\n" + tail
    print(f"::error title={prop(title)}::{esc(body[-15000:])}")
    return 1


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "analyze":
        sys.exit(analyze(sys.argv[2]))
    if mode == "tests":
        sys.exit(tests(sys.argv[2]))
    if mode == "log":
        sys.exit(log(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "log"))
    sys.exit(f"unknown mode {mode}")
