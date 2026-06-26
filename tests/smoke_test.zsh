#!/bin/zsh

set -u

PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cardymccardface-test.XXXXXX")"

fail() {
  print -ru2 -- "Smoke test failed: $*"
  exit 1
}

export PHOTO_IMPORTER_SOURCE_ONLY=true
source "${PROJECT_DIR}/CardyMcCardface/Resources/photo_import.sh" ||
  fail "could not load importer"

test_cleanup() {
  /bin/rm -rf "$TEST_ROOT"
}
trap test_cleanup EXIT INT TERM HUP

LOGFILE="${TEST_ROOT}/test.log"
RUNTIME_ROOT="${TEST_ROOT}/runtime"
LOCK_ROOT="${RUNTIME_ROOT}/locks"
CONFIG_FILE="${TEST_ROOT}/config.plist"
STATUS_FILE="${TEST_ROOT}/status.plist"

command mkdir -p \
  "${TEST_ROOT}/source/100CAMERA/subfolder" \
  "${TEST_ROOT}/source/.hidden" \
  "${TEST_ROOT}/destination"

print -r -- "raw image" > "${TEST_ROOT}/source/100CAMERA/IMAGE_0001.Cr3"
print -r -- "jpeg image" > "${TEST_ROOT}/source/100CAMERA/subfolder/IMAGE_0002.JPEG"
print -r -- "not an image" > "${TEST_ROOT}/source/100CAMERA/notes.txt"
print -r -- "hidden image" > "${TEST_ROOT}/source/.hidden/IMAGE_9999.JPG"
/usr/bin/touch -t 202501020908.07 "${TEST_ROOT}/source/100CAMERA/IMAGE_0001.Cr3"
/usr/bin/touch -t 202602031011.12 "${TEST_ROOT}/source/100CAMERA/subfolder/IMAGE_0002.JPEG"

prepare_runtime || fail "runtime setup"
normalize_capture_date "1970-01-01 00:00:00" &&
  fail "epoch metadata date should be rejected"
normalize_capture_date "2026:01:02 09:08:07" ||
  fail "valid metadata date should be accepted"
[[ "$REPLY" == "2026-01-02" ]] || fail "normalized metadata date"
write_status "importing" "Importing two photos" 2 "${TEST_ROOT}/destination" ||
  fail "status writing"
[[ "$(/usr/bin/plutil -extract state raw -o - "$STATUS_FILE")" == "importing" ]] ||
  fail "status state"
[[ "$(/usr/bin/plutil -extract fileCount raw -o - "$STATUS_FILE")" == "2" ]] ||
  fail "status file count"

/usr/bin/plutil -create xml1 "$CONFIG_FILE"
/usr/bin/plutil -insert destinationRoot -string "${TEST_ROOT}/destination" "$CONFIG_FILE"
/usr/bin/plutil -insert organizationMode -string "shoots" "$CONFIG_FILE"
/usr/bin/plutil -insert dateFolderStyle -string "year-date" "$CONFIG_FILE"
/usr/bin/plutil -insert shootFolderStyle -string "time-volume" "$CONFIG_FILE"
/usr/bin/plutil -insert autoEject -bool false "$CONFIG_FILE"
/usr/bin/plutil -insert checksumVerify -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert dryRun -bool false "$CONFIG_FILE"
/usr/bin/plutil -insert notificationsEnabled -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert minCardSizeGB -integer 8 "$CONFIG_FILE"
/usr/bin/plutil -insert ingestVillageMode -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert stationName -string "Ingest-01" "$CONFIG_FILE"
/usr/bin/plutil -insert operatorName -string "Smoke Test Operator" "$CONFIG_FILE"
/usr/bin/plutil -insert sharedStatusEnabled -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert sharedManifestEnabled -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert sharedLocksEnabled -bool true "$CONFIG_FILE"
/usr/bin/plutil -insert minFreeSpaceGB -integer 0 "$CONFIG_FILE"
load_configuration || fail "configuration loading"

[[ "$DESTINATION_ROOT" == "${TEST_ROOT}/destination" ]] ||
  fail "destination configuration"
[[ "$ORGANIZATION_MODE" == "shoots" ]] || fail "organization configuration"
[[ "$DATE_FOLDER_STYLE" == "year-date" ]] || fail "date style configuration"
[[ "$SHOOT_FOLDER_STYLE" == "time-volume" ]] || fail "shoot style configuration"
[[ "$AUTO_EJECT" == "false" ]] || fail "auto eject configuration"
[[ "$CHECKSUM_VERIFY" == "true" ]] || fail "checksum configuration"
[[ "$NOTIFICATIONS_ENABLED" == "true" ]] || fail "notification configuration"
[[ "$MIN_CARD_SIZE_GB" == "8" ]] || fail "minimum size configuration"
[[ "$INGEST_VILLAGE_MODE" == "true" ]] || fail "ingest village configuration"
[[ "$STATION_NAME" == "Ingest-01" ]] || fail "station configuration"
[[ "$OPERATOR_NAME" == "Smoke Test Operator" ]] || fail "operator configuration"
[[ "$SHARED_STATUS_ENABLED" == "true" ]] || fail "shared status configuration"
[[ "$SHARED_MANIFEST_ENABLED" == "true" ]] || fail "shared manifest configuration"
[[ "$SHARED_LOCKS_ENABLED" == "true" ]] || fail "shared locks configuration"
[[ "$SHARED_STATUS_DIR" == "${DESTINATION_ROOT}/.cardy-status" ]] ||
  fail "shared status directory default"
[[ "$SHARED_MANIFEST_DIR" == "${DESTINATION_ROOT}/.cardy-imports" ]] ||
  fail "shared manifest directory default"
[[ "$SHARED_LOCK_DIR" == "${DESTINATION_ROOT}/.cardy-locks" ]] ||
  fail "shared lock directory default"
preflight_destination_root || fail "destination preflight"
write_shared_status "importing" "Village smoke test" 2 "${TEST_ROOT}/destination" "EXAMPLE_CARD" ||
  fail "shared status writing"
[[ -f "${TEST_ROOT}/destination/.cardy-status/Ingest-01.json" ]] ||
  fail "shared status file missing"
/usr/bin/plutil -convert xml1 -o /dev/null "${TEST_ROOT}/destination/.cardy-status/Ingest-01.json" ||
  fail "shared status JSON syntax"
acquire_shared_lock "example-card-fingerprint" || fail "shared lock acquisition"
shared_lock="$REPLY"
[[ -d "$shared_lock" ]] || fail "shared lock directory missing"
release_shared_lock "$shared_lock"
[[ ! -d "$shared_lock" ]] || fail "shared lock release"

CAPTURE_DATE="2026-01-02"
CAPTURE_TIME="09-08-07"
CAMERA_MODEL="Example Camera"
build_destination "EXAMPLE CARD" || fail "shoot destination building"
[[ "$REPLY" == "${TEST_ROOT}/destination/2026/2026-01-02/09-08-07_EXAMPLE_CARD" ]] ||
  fail "unexpected shoot destination: $REPLY"

ORGANIZATION_MODE="daily"
DATE_FOLDER_STYLE="nested-date"
build_destination "EXAMPLE CARD" || fail "daily destination building"
[[ "$REPLY" == "${TEST_ROOT}/destination/2026/01/02" ]] ||
  fail "unexpected daily destination: $REPLY"

EXIFTOOL_PATH=""
classify_images_by_date "${TEST_ROOT}/source" || fail "image classification"
[[ "$SCAN_COUNT" == "2" ]] || fail "expected two visible images, found ${SCAN_COUNT}"
[[ "${#DATE_KEYS[@]}" == "2" ]] || fail "expected two capture dates"
[[ "${DATE_COUNTS[2025-01-02]}" == "1" ]] || fail "first capture date"
[[ "${DATE_COUNTS[2026-02-03]}" == "1" ]] || fail "second capture date"

manifest="${DATE_MANIFESTS[2025-01-02]}"
run_rsync_manifest \
  "${TEST_ROOT}/source" \
  "${TEST_ROOT}/destination" \
  "$manifest" \
  "${TEST_ROOT}/rsync.log" || fail "rsync execution"
count_rsync_files "${TEST_ROOT}/rsync.log"

[[ "$RSYNC_EXIT_CODE" == "0" ]] || fail "rsync returned ${RSYNC_EXIT_CODE}"
[[ "$COPIED_COUNT" == "1" ]] || fail "expected one copied image, found ${COPIED_COUNT}"
verify_import_manifest \
  "${TEST_ROOT}/source" \
  "${TEST_ROOT}/destination" \
  "$manifest" \
  1 ||
  fail "size and count verification"
[[ "$VERIFIED_COUNT" == "1" ]] || fail "expected one verified image"

verify_checksums_manifest \
  "${TEST_ROOT}/source" \
  "${TEST_ROOT}/destination" \
  "$manifest" \
  "${TEST_ROOT}/checksum.log" || fail "checksum verification"

[[ ! -e "${TEST_ROOT}/destination/100CAMERA/notes.txt" ]] ||
  fail "non-image file was copied"
[[ ! -e "${TEST_ROOT}/destination/.hidden/IMAGE_9999.JPG" ]] ||
  fail "hidden image was copied"
[[ ! -e "${TEST_ROOT}/destination/100CAMERA/subfolder/IMAGE_0002.JPEG" ]] ||
  fail "second date was copied in the first date batch"
remove_date_manifests

CAPTURE_DATE="2026-01-02"
CAPTURE_TIME="09-08-07"
CAMERA_MODEL='Example "Camera"'
ORGANIZATION_MODE="daily"
SCAN_COUNT=2
SCAN_BYTES=20
write_sidecar \
  "${TEST_ROOT}/destination" \
  "EXAMPLE_CARD" \
  "2026-01-03T12:34:56-05:00" \
  1 || fail "sidecar creation"

sidecar=("${TEST_ROOT}/destination"/photo-import-*.json(N))
[[ "${#sidecar[@]}" == "1" ]] || fail "expected one JSON sidecar"
/usr/bin/plutil -convert xml1 -o /dev/null "${sidecar[1]}" ||
  fail "sidecar JSON syntax"

DATE_KEYS=(2026-01-02)
write_shared_import_manifest \
  "complete" \
  "EXAMPLE_CARD" \
  "${TEST_ROOT}/destination" \
  "2026-01-03T12:34:56-05:00" \
  1 \
  2 \
  2 \
  2 \
  20 \
  20 \
  "passed" || fail "shared manifest creation"

shared_manifest=("${TEST_ROOT}/destination/.cardy-imports"/*.json(N))
[[ "${#shared_manifest[@]}" == "1" ]] || fail "expected one shared manifest"
/usr/bin/plutil -convert xml1 -o /dev/null "${shared_manifest[1]}" ||
  fail "shared manifest JSON syntax"

print "Smoke test passed."
