#!/usr/bin/env python3
"""Patch generated Packer inline steps for reproducible local bakes."""

from __future__ import annotations

import json
import sys
from pathlib import Path


REPLACEMENTS = {
    "{{FLAG}}": "FLAG_PLACEHOLDER",
    '{{"{{"}}FLAG{{"}}"}}': "FLAG_PLACEHOLDER",
}

PWNKIT_PINNED_APT = (
    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "
    "--no-install-recommends policykit-1=0.105-26ubuntu1.1 "
    "libpolkit-agent-1-0=0.105-26ubuntu1.1 "
    "libpolkit-gobject-1-0=0.105-26ubuntu1.1"
)

PWNKIT_LAUNCHPAD_DEBS = [
    "https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/21593865/"
    "+files/libpolkit-gobject-1-0_0.105-26ubuntu1.1_amd64.deb",
    "https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/21593865/"
    "+files/libpolkit-agent-1-0_0.105-26ubuntu1.1_amd64.deb",
    "https://launchpad.net/~ubuntu-security/+archive/ubuntu/ppa/+build/21593865/"
    "+files/policykit-1_0.105-26ubuntu1.1_amd64.deb",
]

PWNKIT_ARCHIVED_APT = (
    "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "
    "ca-certificates wget && "
    "tmp=$(mktemp -d) && "
    + " && ".join(f"wget -q -P \"$tmp\" {url}" for url in PWNKIT_LAUNCHPAD_DEBS)
    + " && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades "
    "\"$tmp\"/libpolkit-gobject-1-0_0.105-26ubuntu1.1_amd64.deb "
    "\"$tmp\"/libpolkit-agent-1-0_0.105-26ubuntu1.1_amd64.deb "
    "\"$tmp\"/policykit-1_0.105-26ubuntu1.1_amd64.deb && "
    "rm -rf \"$tmp\""
)


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
        if step == PWNKIT_PINNED_APT:
            step = PWNKIT_ARCHIVED_APT
        patched.append(step)

    path.write_text(json.dumps(patched, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
