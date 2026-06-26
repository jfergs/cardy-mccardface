#!/bin/zsh

set -eu

APP_PATH="${HOME}/Applications/Cardy McCardface.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/CardyMcCardface"
DOMAIN="gui/$(/usr/bin/id -u)"
LEGACY_IMPORTER="${HOME}/Library/LaunchAgents/com.cardymccardface.photoimporter.plist"
LEGACY_STATUS="${HOME}/Library/LaunchAgents/com.cardymccardface.statusitem.plist"

if [[ -x "$APP_EXECUTABLE" ]]; then
  "$APP_EXECUTABLE" --unregister-login 2>/dev/null || true
fi

/usr/bin/pkill -f "$APP_EXECUTABLE" 2>/dev/null || true
/bin/launchctl bootout "$DOMAIN" "$LEGACY_IMPORTER" 2>/dev/null || true
/bin/launchctl bootout "$DOMAIN" "$LEGACY_STATUS" 2>/dev/null || true
/bin/rm -f "$LEGACY_IMPORTER" "$LEGACY_STATUS"
/bin/rm -rf "$APP_PATH" "${HOME}/Applications/Cardy McCardface Status.app"

print "Uninstalled Cardy McCardface."
print "Settings, logs, and imported photos were retained."
