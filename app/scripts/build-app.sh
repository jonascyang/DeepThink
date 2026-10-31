#!/bin/zsh
# Builds ThinkMyDay.app (universal) and signs it.
#
#   SIGN_IDENTITY="ThinkMyDay Local Signing" ./scripts/build-app.sh   # fixed self-signed certificate
#   ./scripts/build-app.sh                                            # ad-hoc signature (identity changes every build)
#
# INSTALL_DIR (default ~/Applications) receives the app; an existing copy is replaced in place.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
IDENTITY="${SIGN_IDENTITY:--}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP="$ROOT/build/ThinkMyDay.app"
BUILD_NUMBER=$(date +%Y%m%d%H%M%S)

swift build -c release --arch arm64 --arch x86_64 --product ThinkMyDay
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/ThinkMyDay"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ThinkMyDay"
sed "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" --identifier com.jonascyang.thinkmyday "$APP"
codesign --verify --verbose=2 "$APP"
echo "Designated requirement:"
codesign --display --requirements - "$APP" 2>&1 | sed -n 's/^#* *designated => /  /p'

mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/ThinkMyDay.app"
if pgrep -f "$TARGET/Contents/MacOS/ThinkMyDay" >/dev/null; then
  pkill -f "$TARGET/Contents/MacOS/ThinkMyDay" || true
  sleep 1
fi
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"
echo "Installed $TARGET (build $BUILD_NUMBER, identity: $IDENTITY)"
