#!/bin/zsh

set -eu

PROJECT_DIR="${0:A:h}"
INSTALL_DIR="${HOME}/Library/Scripts/CardyMcCardface"
AGENT_DIR="${HOME}/Library/LaunchAgents"
LOG_DIR="${HOME}/Library/Logs"
LABEL="com.cardymccardface.photoimporter"
PLIST_NAME="${LABEL}.plist"
DOMAIN="gui/$(/usr/bin/id -u)"

print "Installing Cardy McCardface..."

command mkdir -p "$INSTALL_DIR" "$AGENT_DIR" "$LOG_DIR"
/bin/cp "$PROJECT_DIR/photo_import.sh" "$INSTALL_DIR/photo_import.sh"
/bin/cp "$PROJECT_DIR/$PLIST_NAME" "$AGENT_DIR/$PLIST_NAME"
command chmod 755 "$INSTALL_DIR/photo_import.sh"
command chmod 644 "$AGENT_DIR/$PLIST_NAME"

/usr/bin/plutil -lint "$AGENT_DIR/$PLIST_NAME"
/bin/launchctl bootout "$DOMAIN" "$AGENT_DIR/$PLIST_NAME" 2>/dev/null || true
/bin/launchctl bootstrap "$DOMAIN" "$AGENT_DIR/$PLIST_NAME"
/bin/launchctl enable "${DOMAIN}/${LABEL}"

print "Installed and loaded ${LABEL}."
print "Edit configuration in: ${INSTALL_DIR}/photo_import.sh"
print "Log file: ${LOG_DIR}/CardyMcCardface.log"
