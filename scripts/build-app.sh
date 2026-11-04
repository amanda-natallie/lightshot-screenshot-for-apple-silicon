#!/usr/bin/env bash
# Builds build/<APP_NAME>.app (native arm64). Usage: scripts/build-app.sh [--install]
#
# Env (also read from a gitignored .env.local, unless SKIP_ENV_LOCAL=1):
#   APP_NAME         bundle/display name (default: Shotmark)
#   SIGN_IDENTITY    codesign identity; default: LOCAL_SIGN_NAME if in the keychain, else ad-hoc ("-")
#   LOCAL_SIGN_NAME  local certificate name (default: "Shotmark Local Signing", see scripts/create-signing-cert.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env.local && -z "${SKIP_ENV_LOCAL:-}" ]]; then
  set -a; source .env.local; set +a
fi
APP_NAME=${APP_NAME:-Shotmark}
LOCAL_SIGN_NAME=${LOCAL_SIGN_NAME:-Shotmark Local Signing}
APP="build/$APP_NAME.app"

swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Shotmark" "$APP/Contents/MacOS/Shotmark"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"

# Icon
ICON_TMP=$(mktemp -d)
swift scripts/make-icon.swift "$ICON_TMP/icon.png"
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICON_TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ICON_TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

# A stable identity keeps the Screen Recording grant across rebuilds; ad-hoc signatures change every build.
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk -v n="\"$LOCAL_SIGN_NAME\"" 'index($0, n) {print $2; exit}')
  SIGN_IDENTITY=${SIGN_IDENTITY:--}
fi
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
codesign -dr - "$APP" 2>&1 | tail -1
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Shotmark"))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Shotmark 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  rm -rf "$APP"  # keep a single copy so Spotlight and TCC only see the installed one
  echo "Installed /Applications/$APP_NAME.app"
fi
