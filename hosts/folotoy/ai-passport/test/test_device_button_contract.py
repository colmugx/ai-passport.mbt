"""SDK boundary tests for the FoloToy AI Passport host assets.

Guards the application-generic host contract that the real ESP-IDF build
cannot prove on hosts:

  * no application-specific vocabulary leaks into any host C/header/build
    source (the FoloToy BSP is an external dependency and its source is
    never tracked inside this tree)
  * main/app_main.c references only the generic ai_passport_mbt_* device
    ABI and none of the retired application-specific symbol names
  * the pinned hardware baselines hold: factory app partition 0x380000 at
    0x10000, sdkconfig pins esp32c3 / 8 MB flash / CONFIG_FREERTOS_HZ=1000
  * third-party hardware code stays external: no BSP sources and no
    generated upstream.cmake tracked in the tree, no template-specific
    dependency path hardcoded in the CLI sources
"""

import re
import unittest
from pathlib import Path

HOST_ROOT = Path(__file__).resolve().parent.parent
SDK_ROOT = HOST_ROOT.parent.parent.parent
MAIN = HOST_ROOT / "main" / "app_main.c"
BSP_MANIFEST = HOST_ROOT / "components" / "folotoy_bsp" / "bsp.sha256"
CLI_SOURCES = sorted(
    (SDK_ROOT / "src" / "cli").glob("*.mbt")
) + sorted((SDK_ROOT / "src" / "cmd" / "passport").glob("*.mbt"))

FORBIDDEN_VOCABULARY = ("forest", "fairy", "parallax", "bpm")

# The complete generic device ABI app_main.c may reference. Everything the
# C side calls into MoonBit must appear in this set.
ALLOWED_MOONBIT_SYMBOLS = {
    "ai_passport_mbt_probe",
    "ai_passport_mbt_app_init",
    "ai_passport_mbt_app_update",
    "ai_passport_mbt_app_draw",
    "ai_passport_mbt_app_present",
    "ai_passport_mbt_input_press",
    "ai_passport_mbt_audio_volume",
    "ai_passport_mbt_audio_muted",
}


def host_source_files():
    """Every .c/.h/.txt under the host tree, vendored upstream excluded."""
    for path in sorted(HOST_ROOT.rglob("*")):
        if path.suffix not in (".c", ".h", ".txt"):
            continue
        if "upstream" in path.relative_to(HOST_ROOT).parts:
            continue
        yield path


class BoundaryVocabularyTests(unittest.TestCase):
    def test_no_application_vocabulary_in_host_sources(self):
        offenders = []
        for path in host_source_files():
            text = path.read_text(errors="replace").lower()
            for word in FORBIDDEN_VOCABULARY:
                if word in text:
                    offenders.append(
                        f"{path.relative_to(HOST_ROOT)}: {word}"
                    )
        self.assertEqual(
            offenders,
            [],
            "host assets must stay application-generic",
        )


class DeviceAbiBoundaryTests(unittest.TestCase):
    def test_app_main_references_only_the_generic_abi(self):
        code = MAIN.read_text(errors="replace")
        referenced = set(re.findall(r"ai_passport_mbt_\w+", code))
        self.assertEqual(
            referenced,
            ALLOWED_MOONBIT_SYMBOLS,
            "app_main.c must reference exactly the generic device ABI",
        )
        for retired in ("forest_init", "forest_update", "forest_draw",
                        "forest_present"):
            self.assertNotIn(
                retired, code,
                f"retired application-specific symbol '{retired}' must not "
                "appear in app_main.c",
            )


class BspSubmoduleBoundaryTests(unittest.TestCase):
    def test_no_bsp_sources_tracked_inside_the_host_tree(self):
        upstream = HOST_ROOT / "components" / "folotoy_bsp" / "upstream"
        self.assertFalse(
            upstream.exists(),
            "BSP sources must come from an external checkout, never be "
            "tracked under components/folotoy_bsp/upstream/",
        )
        generated = HOST_ROOT / "components" / "folotoy_bsp" / "upstream.cmake"
        self.assertFalse(
            generated.exists(),
            "upstream.cmake is generated per build into the workspace; the "
            "tracked tree must not carry one",
        )

    def test_bsp_manifest_is_well_formed(self):
        lines = [
            line.strip()
            for line in BSP_MANIFEST.read_text().splitlines()
            if line.strip()
        ]
        self.assertTrue(lines, "bsp.sha256 must not be empty")
        for line in lines:
            digest, _, path = line.partition(" ")
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertIn(
                path,
                {f"include/{name}" for name in (
                    "bsp_audio.h", "bsp_battery.h", "bsp_button.h",
                    "bsp_display.h", "bsp_i2c.h", "bsp_pins.h",
                )}
                | {f"src/{name}" for name in (
                    "bsp_audio.c", "bsp_battery.c", "bsp_button.c",
                    "bsp_display.c", "bsp_display_lvgl.c", "bsp_i2c.c",
                )},
                f"unexpected manifest entry: {path}",
            )

    def test_cli_sources_hardcode_no_template_dependency_path(self):
        offenders = []
        for path in CLI_SOURCES:
            if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
                continue
            text = path.read_text(errors="replace")
            if "external/folotoy" in text:
                offenders.append(path.relative_to(SDK_ROOT))
        self.assertEqual(
            offenders,
            [],
            "dependency paths belong to the project contract "
            "(hostDependencies), never hardcoded CLI defaults",
        )


class HardwareBaselineTests(unittest.TestCase):
    def test_factory_app_partition_is_pinned(self):
        rows = {}
        for line in (HOST_ROOT / "partitions.csv").read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            fields = [field.strip() for field in line.split(",")]
            rows[fields[0]] = fields
        factory = rows["factory"]
        self.assertEqual(factory[1], "app")
        self.assertEqual(factory[2], "factory")
        self.assertEqual(factory[3], "0x10000")
        self.assertEqual(factory[4], "0x380000")

    def test_sdkconfig_pins_target_flashsize_and_tick_rate(self):
        config = {}
        for line in (HOST_ROOT / "sdkconfig.defaults").read_text().splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip()
        self.assertEqual(config.get("CONFIG_IDF_TARGET"), '"esp32c3"')
        self.assertEqual(config.get("CONFIG_ESPTOOLPY_FLASHSIZE_8MB"), "y")
        self.assertEqual(config.get("CONFIG_FREERTOS_HZ"), "1000")


if __name__ == "__main__":
    unittest.main()
