#!/usr/bin/env python3
"""Update the lab-local component -> Glance UUID registry."""

from __future__ import annotations

import datetime as dt
import sys
from pathlib import Path

import yaml


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: update_built_uuids.py <component_id> <glance_uuid> <gamma4_sha> <path>",
            file=sys.stderr,
        )
        return 2

    component_id, image_id, gamma4_sha, registry_path = sys.argv[1:5]
    path = Path(registry_path)

    with path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}

    data.setdefault("schema_version", "1.0")
    data.setdefault("built_images", {})
    data["built_images"][component_id] = {
        "glance_image_id": image_id,
        "built_at": dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "gamma4_sha": gamma4_sha,
    }

    with path.open("w", encoding="utf-8") as fh:
        yaml.safe_dump(data, fh, sort_keys=False)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
