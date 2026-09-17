#!/usr/bin/env bash
# CI-only pre-release proof: copy the pinned public template and replace
# ONLY its runtime-adapter boundary (src/runtime_wasm + src/runtime_native
# + the deviceEntry contract field) with the single-entry application
# contract. Nothing here is ever committed to the template; CI builds the
# copy against the current SDK to prove the template is ready to migrate.
# Usage: template-single-entry.sh <template-checkout> <destination>
set -euo pipefail

src="$(cd "$1" && pwd)"
dst="$2"

rm -rf "$dst"
mkdir -p "$(dirname "$dst")"
cp -R "$src" "$dst"

rm -rf "$dst/src/runtime_wasm" "$dst/src/runtime_native"
rm -rf "$dst/_build" "$dst/.passport" "$dst/passport-generated"

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

# One application entry serves every Host; assets and hostDependencies are
# preserved verbatim. Generated Host entries are project packages, so the
# module source root becomes the project root and intra-module import
# paths gain the src/ prefix. The app package additionally imports the
# application contract.
python3 - "$dst" <<'EOF'
import json, re, sys

root = sys.argv[1]

mod_path = f"{root}/moon.mod"
mod = open(mod_path).read()
mod = re.sub(r'^source = "src"\n', "", mod, count=1, flags=re.M)
open(mod_path, "w").write(mod)

for pkg in (f"{root}/src/app/moon.pkg", f"{root}/src/forest_walk/moon.pkg"):
    text = open(pkg).read()
    text = text.replace(
        '"colmugx/ai-passport-template/', '"colmugx/ai-passport-template/src/'
    )
    if pkg.endswith("src/app/moon.pkg"):
        text = text.replace(
            "import {", 'import {\n  "colmugx/ai-passport/application",', 1
        )
    open(pkg, "w").write(text)

contract_path = f"{root}/passport.json"
contract = json.load(open(contract_path))
contract["entry"] = "src/app"
contract.pop("deviceEntry", None)
with open(contract_path, "w") as handle:
    json.dump(contract, handle, indent=2)
    handle.write("\n")
EOF

echo "single-entry transform: $dst (entry src/app, runtime adapters removed)"
