#!/usr/bin/env python3
"""
Reads subscriptions JSON from stdin, expands file globs, patches remarks,
merges configs into ~/vpn/subscriptions/<name>/configs.json.
Prints publish_users JSON ([{name, token}]) to stdout.
"""
import glob
import json
import os
import sys
from pathlib import Path


def expand(pattern):
    return sorted(
        f for f in glob.glob(os.path.expanduser(pattern)) if os.path.isfile(f)
    )


subscriptions = json.load(sys.stdin)
publish_users = []

for sub in subscriptions:
    name, token = sub["name"], sub["token"]
    out_dir = Path.home() / "vpn" / "subscriptions" / name
    out_dir.mkdir(parents=True, exist_ok=True)

    configs = []
    for entry in sub["files"]:
        for path in expand(entry["path"]):
            config = json.loads(Path(path).read_text())
            if "remark" in entry:
                config["remarks"] = entry["remark"]
            configs.append(config)

    if configs:
        (out_dir / "configs.json").write_text(json.dumps(configs, indent=2))
        print(f"  {name}: merged {len(configs)} file(s)", file=sys.stderr)
    else:
        print(f"  {name}: WARNING — no files matched", file=sys.stderr)

    publish_users.append({"name": name, "token": token})

print(json.dumps(publish_users))
