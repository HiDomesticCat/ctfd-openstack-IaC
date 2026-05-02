#!/usr/bin/env python3
"""Escape literal Go-template-looking placeholders in Packer inline steps."""

from __future__ import annotations

import json
import sys
from pathlib import Path


REPLACEMENTS = {
    "{{FLAG}}": "FLAG_PLACEHOLDER",
    '{{"{{"}}FLAG{{"}}"}}': "FLAG_PLACEHOLDER",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_packer_inline_literals.py <steps.json>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    steps = json.loads(path.read_text(encoding="utf-8"))
    patched = []
    for step in steps:
        for old, new in REPLACEMENTS.items():
            step = step.replace(old, new)
        patched.append(step)

    path.write_text(json.dumps(patched, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
