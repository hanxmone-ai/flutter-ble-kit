"""Turns the tail of CI log files into GitHub annotations.

Usage: python3 tool/ci_annotate.py LEVEL FILE [FILE...]   (LEVEL: error, warning or notice)

Annotations are readable through the checks API, which is handy when the raw logs are not.
"""

import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
MAX_LINES = 150

level, *files = sys.argv[1:]
for name in files:
    path = Path(name)
    if not path.exists():
        continue
    lines = ANSI.sub("", path.read_text(errors="replace")).splitlines()[-MAX_LINES:]
    body = "\n".join(lines).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::{level} title={path.name}::{body}")
