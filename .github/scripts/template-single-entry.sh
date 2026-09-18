#!/usr/bin/env bash
# CI-only pre-release proof: copy the pinned public template and migrate it
# to the single-entry application contract — remove the downstream runtime
# adapters, implement the SDK application contract in the app package, and
# point `entry` at it. The project keeps `source = "src"` and every authored
# import; nothing here is ever committed to the template.
# Usage: template-single-entry.sh <template-checkout> <destination>
set -euo pipefail

src="$(cd "$1" && pwd)"
dst="$2"

rm -rf "$dst"
mkdir -p "$(dirname "$dst")"
cp -R "$src" "$dst"

rm -rf "$dst/src/runtime_wasm" "$dst/src/runtime_native"
rm -rf "$dst/_build" "$dst/.passport" "$dst/passport-generated" "$dst/src/passport-generated"

cat > "$dst/src/app/passport_contract.mbt" <<'EOF'
///|
/// Application-contract adapter (CI transform only): every application
/// semantic stays in App; the contract methods forward the host facts and
/// the desired output state.
impl @application.Application for App with fn update(
  self,
  ctx : @application.FrameContext,
) -> Unit {
  self.advance(
    ctx.now_us,
    playback_position_us?=ctx.playback_position_us,
    presentation_lead_us=ctx.presentation_lead_us,
  )
}

///|
impl @application.Application for App with fn button(
  self,
  button : @input.Button,
  pressed : Bool,
) -> Unit {
  self.input(button, pressed)
}

///|
impl @application.Application for App with fn render(
  self,
  battery_percent : Int?,
) -> @graphics.FrameView {
  self.draw(battery_percent=battery_percent)
  self.frame_view()
}

///|
impl @application.Application for App with fn audio_output(
  self,
) -> @application.AudioOutput? {
  Some({ volume: self.volume(), muted: self.muted() })
}

///|
pub fn passport_main() -> &@application.Application {
  App::new()
}
EOF

# The app package gains the SDK application contract import; all existing
# imports stay as authored.
python3 - "$dst" <<'EOF'
import json, sys

root = sys.argv[1]

pkg_path = f"{root}/src/app/moon.pkg"
text = open(pkg_path).read()
text = text.replace("import {", 'import {\n  "colmugx/ai-passport/application",', 1)
open(pkg_path, "w").write(text)

contract_path = f"{root}/passport.json"
contract = json.load(open(contract_path))
contract["entry"] = "app"
contract.pop("deviceEntry", None)
with open(contract_path, "w") as handle:
    json.dump(contract, handle, indent=2)
    handle.write("\n")
EOF

echo "single-entry transform: $dst (entry app, runtime adapters removed)"
