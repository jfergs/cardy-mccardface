#!/bin/zsh

set -eu

INSTALL_DIR="${HOME}/Library/Scripts/CardyMcCardface"
AGENT_DIR="${HOME}/Library/LaunchAgents"
LABEL="com.cardymccardface.photoimporter"
PLIST="${AGENT_DIR}/${LABEL}.plist"
DOMAIN="gui/$(/usr/bin/id -u)"

/bin/launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
/bin/rm -f "$PLIST" "${INSTALL_DIR}/photo_import.sh"
/bin/rmdir "$INSTALL_DIR" 2>/dev/null || true

print "Uninstalled ${LABEL}."
print "Logs were retained in ${HOME}/Library/Logs."
