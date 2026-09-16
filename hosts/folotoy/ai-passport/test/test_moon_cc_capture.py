import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parent.parent / "tools" / "moon_cc_capture.py"


class CaptureCompilerTests(unittest.TestCase):
    def test_response_file_captures_all_sources_and_graph_outputs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build = root / "_build" / "native" / "release" / "build"
            build.mkdir(parents=True)
            (build / "first.c").write_text("int first(void) { return 1; }\n")
            (build / "second.c").write_text("int second(void) { return 2; }\n")
            (root / "nested.rsp").write_text("_build/native/release/build/second.c -MF deps.d")
            (root / "args.rsp").write_text(
                "_build/native/release/build/first.c @nested.rsp -o output/placeholder.exe"
            )
            capture = root / "generated"
            env = {**os.environ, "MOON_CC_CAPTURE_DIR": str(capture)}
            subprocess.run(
                [sys.executable, str(SCRIPT), "@args.rsp"],
                cwd=root,
                env=env,
                check=True,
            )
            self.assertEqual(
                (capture / "sources.txt").read_text().splitlines(),
                ["native/release/build/first.c", "native/release/build/second.c"],
            )
            self.assertEqual((root / "output/placeholder.exe").stat().st_size, 0)
            self.assertTrue((root / "deps.d").is_file())
            trace = json.loads((capture / "capture-invocations.jsonl").read_text())
            self.assertEqual(
                trace["response_files"],
                [str((root / "args.rsp").resolve()), str((root / "nested.rsp").resolve())],
            )
            self.assertEqual(trace["output"], "output/placeholder.exe")
            self.assertEqual(trace["depfile"], "deps.d")

    def test_rejects_non_generated_c(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "host.c").write_text("int host(void) { return 1; }\n")
            env = {**os.environ, "MOON_CC_CAPTURE_DIR": str(root / "generated")}
            result = subprocess.run(
                [sys.executable, str(SCRIPT), "host.c", "-o", "fake.o"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("outside Moon's generated _build", result.stderr)
            self.assertFalse((root / "fake.o").exists())


if __name__ == "__main__":
    unittest.main()
