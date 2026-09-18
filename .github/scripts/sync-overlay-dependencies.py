#!/usr/bin/env python3
"""Expose an unpublished SDK's direct dependencies to an overlay project.

Moon resolves registry dependency metadata for the project's pinned SDK
version before tests replace that package's source tree. If the unpublished
SDK adds a dependency, the old registry metadata cannot name it. This helper
adds only missing SDK direct imports to the downstream test module so
`moon update` can materialize the dependency graph the next release will
publish.
"""

from __future__ import annotations

from pathlib import Path
import re
import sys


ENTRY = re.compile(r'^\s*"([^"]+@[^"]+)",\s*$')


def import_block(lines: list[str], path: Path) -> tuple[int, int, list[str]]:
    start = next(
        (index for index, line in enumerate(lines) if line.strip() == "import {"),
        None,
    )
    if start is None:
        raise SystemExit(f"{path}: no import block")
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if lines[index].strip() == "}"
        ),
        None,
    )
    if end is None:
        raise SystemExit(f"{path}: unterminated import block")

    entries: list[str] = []
    for line in lines[start + 1 : end]:
        match = ENTRY.match(line)
        if match:
            entries.append(match.group(1))
    return start, end, entries


def module_name(spec: str) -> str:
    return spec.rsplit("@", 1)[0]


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(
            "usage: sync-overlay-dependencies.py <sdk-moon.mod> <project-moon.mod>",
        )

    sdk_path = Path(sys.argv[1])
    project_path = Path(sys.argv[2])
    sdk_lines = sdk_path.read_text(encoding="utf-8").splitlines()
    project_text = project_path.read_text(encoding="utf-8")
    project_lines = project_text.splitlines()

    _, _, sdk_imports = import_block(sdk_lines, sdk_path)
    _, project_end, project_imports = import_block(project_lines, project_path)
    present = {module_name(spec) for spec in project_imports}
    missing = [spec for spec in sdk_imports if module_name(spec) not in present]

    if not missing:
        return

    additions = [f'  "{spec}",' for spec in missing]
    project_lines[project_end:project_end] = additions
    trailing_newline = "\n" if project_text.endswith("\n") else ""
    project_path.write_text(
        "\n".join(project_lines) + trailing_newline,
        encoding="utf-8",
    )
    print(
        f"{project_path}: added overlay dependencies: {', '.join(missing)}",
    )


if __name__ == "__main__":
    main()
