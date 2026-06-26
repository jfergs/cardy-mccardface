#!/bin/zsh

set -eu

PROJECT_DIR="${0:A:h}"
PROJECT="${PROJECT_DIR}/CardyMcCardface.xcodeproj"
SCHEME="CardyMcCardface"
DERIVED_DATA="${TMPDIR:-/tmp}/CardyMcCardfaceDerivedData"
BUILT_APP="${DERIVED_DATA}/Build/Products/Release/Cardy McCardface.app"
APP_PATH="${HOME}/Applications/Cardy McCardface.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/CardyMcCardface"
DOMAIN="gui/$(/usr/bin/id -u)"
LEGACY_IMPORTER="${HOME}/Library/LaunchAgents/com.cardymccardface.photoimporter.plist"
LEGACY_STATUS="${HOME}/Library/LaunchAgents/com.cardymccardface.statusitem.plist"

print "Building Cardy McCardface with Xcode..."

/usr/bin/xcodebuild -version >/dev/null 2>&1 || {
  print -ru2 -- "A working Xcode installation is required."
  exit 1
}

/usr/bin/xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "$BUILT_APP" ]] || {
  print -ru2 -- "Xcode did not produce the expected app: $BUILT_APP"
  exit 1
}

# Remove development-era background jobs and generated app variants.
/bin/launchctl bootout "$DOMAIN" "$LEGACY_IMPORTER" 2>/dev/null || true
/bin/launchctl bootout "$DOMAIN" "$LEGACY_STATUS" 2>/dev/null || true
/usr/bin/pkill -f "Cardy McCardface Status.app/Contents/MacOS" 2>/dev/null || true
/usr/bin/pkill -f "${APP_EXECUTABLE}" 2>/dev/null || true
/usr/bin/pkill -f "Cardy McCardface.app/Contents/Resources/photo_import.sh" 2>/dev/null || true
/bin/rm -f "$LEGACY_IMPORTER" "$LEGACY_STATUS"
/bin/rm -rf "${HOME}/Applications/Cardy McCardface Status.app"

command mkdir -p "${HOME}/Applications"
/bin/rm -rf "$APP_PATH"
/usr/bin/ditto "$BUILT_APP" "$APP_PATH"
command chmod 755 \
  "$APP_EXECUTABLE" \
  "$APP_PATH/Contents/Resources/photo_import.sh" \
  "$APP_PATH/Contents/Resources/dashboard.sh"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_PATH"
/usr/bin/open -na "$APP_PATH"

print "Installed: ${APP_PATH}"
