#!/usr/bin/env python3
"""CI-only migration of the pinned public template contract to passport.toml."""

from __future__ import annotations

import json
from pathlib import Path
import sys


def toml_string(value: str) -> str:
    # JSON basic-string escaping is a valid TOML basic-string subset for the
    # contract's string values (including \u/\U escapes).
    return json.dumps(value, ensure_ascii=True)


def require_string(obj: dict, key: str, where: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"{where}.{key} must be a non-empty string")
    return value


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: passport-json-to-toml.py <project-root>")

    root = Path(sys.argv[1])
    source = root / "passport.json"
    target = root / "passport.toml"
    if not source.is_file():
        raise SystemExit(f"missing legacy contract: {source}")
    if target.exists():
        raise SystemExit(f"refusing to overwrite existing contract: {target}")

    contract = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(contract, dict):
        raise SystemExit("passport.json root must be an object")

    lines = [f"entry = {toml_string(require_string(contract, 'entry', 'passport.json'))}"]
    device_entry = contract.get("deviceEntry")
    if device_entry is not None:
        if not isinstance(device_entry, str) or not device_entry:
            raise SystemExit("passport.json.deviceEntry must be a non-empty string")
        lines.append(f"deviceEntry = {toml_string(device_entry)}")

    assets = contract.get("assets", [])
    if not isinstance(assets, list):
        raise SystemExit("passport.json.assets must be an array")
    for index, asset in enumerate(assets):
        if not isinstance(asset, dict):
            raise SystemExit(f"passport.json.assets[{index}] must be an object")
        lines.extend(
            [
                "",
                "[[assets]]",
                f"source = {toml_string(require_string(asset, 'source', f'passport.json.assets[{index}]'))}",
                f"bundlePath = {toml_string(require_string(asset, 'bundlePath', f'passport.json.assets[{index}]'))}",
            ],
        )
        if "pcmLoop" in asset:
            pcm_loop = asset["pcmLoop"]
            if not isinstance(pcm_loop, bool):
                raise SystemExit(f"passport.json.assets[{index}].pcmLoop must be boolean")
            lines.append(f"pcmLoop = {'true' if pcm_loop else 'false'}")

    dependencies = contract.get("hostDependencies", {})
    if not isinstance(dependencies, dict):
        raise SystemExit("passport.json.hostDependencies must be an object")
    for host_id in sorted(dependencies):
        dependency = dependencies[host_id]
        if not isinstance(dependency, dict):
            raise SystemExit(
                f"passport.json.hostDependencies[{host_id!r}] must be an object",
            )
        lines.extend(
            [
                "",
                f"[hostDependencies.{toml_string(host_id)}]",
                f"path = {toml_string(require_string(dependency, 'path', f'passport.json.hostDependencies[{host_id!r}]'))}",
            ],
        )

    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    source.unlink()


if __name__ == "__main__":
    main()
