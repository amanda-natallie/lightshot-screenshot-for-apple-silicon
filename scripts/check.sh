#!/usr/bin/env bash
# Full check: unit tests + app bundle build + architecture assertion.
set -euo pipefail
cd "$(dirname "$0")/.."

# Command Line Tools ship the swift-testing macro plugin outside the default search path.
PLUGIN_ARGS=()
CLT_PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ -d "$CLT_PLUGINS" ]] && ! xcode-select -p | grep -q Xcode.app; then
  PLUGIN_ARGS=(-Xswiftc -plugin-path -Xswiftc "$CLT_PLUGINS")
fi

swift test "${PLUGIN_ARGS[@]}"
APP_NAME=Shotmark SKIP_ENV_LOCAL=1 scripts/build-app.sh
archs=$(lipo -archs build/Shotmark.app/Contents/MacOS/Shotmark)
[[ "$archs" == "arm64" ]] || { echo "expected arm64, got: $archs" >&2; exit 1; }
echo "check OK"
