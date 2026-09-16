#!/usr/bin/env python3
"""Capture MoonBit C-backend inputs; never compile or link host objects.

Moon invokes this as the device package's native `options.link.native.cc`.
The placeholder output exists solely to satisfy Moon's own build graph. The
ESP-IDF component reads only `sources.txt` and the copied .c files.
"""

import fcntl
import json
import os
from pathlib import Path
import shlex
import shutil
import sys


def expand_response_files(args, cwd, response_files, seen=None):
    seen = set() if seen is None else seen
    expanded = []
    for arg in args:
        if not arg.startswith("@"):
            expanded.append(arg)
            continue
        path = (cwd / arg[1:]).resolve()
        if path in seen:
            raise ValueError(f"recursive response file: {path}")
        seen.add(path)
        response_files.append(str(path))
        expanded.extend(expand_response_files(shlex.split(path.read_text()), cwd, response_files, seen))
        seen.remove(path)
    return expanded


def parse_compiler_args(args):
    sources = []
    output = None
    depfile = None
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in ("-o", "-MF"):
            if index + 1 >= len(args):
                raise ValueError(f"missing argument after {arg}")
            value = args[index + 1]
            if arg == "-o":
                output = value
            else:
                depfile = value
            index += 2
            continue
        if arg.startswith("-o") and len(arg) > 2:
            output = arg[2:]
        elif arg.startswith("-MF") and len(arg) > 3:
            depfile = arg[3:]
        elif arg.endswith(".c"):
            sources.append(arg)
        index += 1
    return sources, output, depfile


def atomic_write(path, data):
    temporary = path.with_name(path.name + f".tmp-{os.getpid()}")
    temporary.write_bytes(data)
    temporary.replace(path)


def main():
    cwd = Path.cwd().resolve()
    capture_dir = os.environ.get("MOON_CC_CAPTURE_DIR")
    if not capture_dir:
        # Normal root-module native tests also discover this package. In that
        # mode this executable is an honest host compiler driver; the device
        # build always sets the capture directory and never uses host objects.
        os.execvp("cc", ["cc", *sys.argv[1:]])
    destination = Path(capture_dir).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    response_files = []
    expanded = expand_response_files(sys.argv[1:], cwd, response_files)
    sources, output, depfile = parse_compiler_args(expanded)
    if not sources:
        raise ValueError("Moon invoked capture cc with no C input")

    record = {
        "argv": sys.argv[1:],
        "c_sources": sources,
        "cwd": str(cwd),
        "depfile": depfile,
        "expanded_argv": expanded,
        "output": output,
        "response_files": response_files,
    }

    # Moon's generated C lives below the root module's _build directory.
    # Copy its relative path to avoid basename collisions across packages.
    build_root = cwd / "_build"
    copied = []
    for source_arg in sources:
        source = (cwd / source_arg).resolve()
        try:
            relative = source.relative_to(build_root)
        except ValueError as error:
            raise ValueError(f"C input is outside Moon's generated _build: {source}") from error
        if not source.is_file():
            raise FileNotFoundError(source)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        copied.append(relative.as_posix())

    # Each invocation updates the source manifest and trace under one lock.
    # The trace is intentionally ignored: it records the real compiler contract.
    with (destination / ".manifest.lock").open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        manifest = destination / "sources.txt"
        known = set(manifest.read_text().splitlines()) if manifest.exists() else set()
        known.update(copied)
        atomic_write(manifest, ("\n".join(sorted(known)) + "\n").encode())
        with (destination / "capture-invocations.jsonl").open("a") as trace:
            trace.write(json.dumps(record, sort_keys=True) + "\n")

    # Empty placeholders are Moon-internal graph products, never ESP-IDF inputs.
    if output:
        output_path = (cwd / output).resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_bytes(b"")
    if depfile:
        dep_path = (cwd / depfile).resolve()
        dep_path.parent.mkdir(parents=True, exist_ok=True)
        dep_path.write_text(f"{output or 'moon_cc_capture'}: {' '.join(sources)}\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"moon_cc_capture: {error}", file=sys.stderr)
        sys.exit(1)
