#!/usr/bin/env python3
"""Patch gamma4-lab's Packer template for Packer versions without env()."""

from __future__ import annotations

import sys
from pathlib import Path


VARIABLE_BLOCK = '''
variable "root_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "attacker_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "extra_user_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "victim_password" {
  type      = string
  sensitive = true
  default   = ""
}

'''


REPLACEMENTS = {
    '${env("ROOT_PASSWORD")}': "${var.root_password}",
    '${env("ATTACKER_PASSWORD")}': "${var.attacker_password}",
    '${env("EXTRA_USER_PASSWORD")}': "${var.extra_user_password}",
    '${env("VICTIM_PASSWORD")}': "${var.victim_password}",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_packer_env_vars.py <research-vm-base.pkr.hcl>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")

    for old, new in REPLACEMENTS.items():
        text = text.replace(old, new)

    if 'variable "root_password"' not in text:
        marker = "locals {\n"
        if marker in text:
            text = text.replace(marker, VARIABLE_BLOCK + marker, 1)
        else:
            text += "\n" + VARIABLE_BLOCK

    path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
