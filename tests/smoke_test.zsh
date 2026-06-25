#!/bin/zsh

set -u

PROJECT_DIR="${0:A:h:h}"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/cardymccardface-test.XXXXXX")"

fail() {
  print -ru2 -- "Smoke test failed: $*"
  exit 1
}

export PHOTO_IMPORTER_SOURCE_ONLY=true
source "${PROJECT_DIR}/photo_import.sh" || fail "could not load importer"

test_cleanup() {
  /bin/rm -rf "$TEST_ROOT"
}
trap test_cleanup EXIT INT TERM HUP

LOGFILE="${TEST_ROOT}/test.log"
RUNTIME_ROOT="${TEST_ROOT}/runtime"
LOCK_ROOT="${RUNTIME_ROOT}/locks"

command mkdir -p \
  "${TEST_ROOT}/source/100CAMERA/subfolder" \
  "${TEST_ROOT}/source/.hidden" \
  "${TEST_ROOT}/destination"

print -r -- "raw image" > "${TEST_ROOT}/source/100CAMERA/IMAGE_0001.Cr3"
print -r -- "jpeg image" > "${TEST_ROOT}/source/100CAMERA/subfolder/IMAGE_0002.JPEG"
print -r -- "not an image" > "${TEST_ROOT}/source/100CAMERA/notes.txt"
print -r -- "hidden image" > "${TEST_ROOT}/source/.hidden/IMAGE_9999.JPG"

prepare_runtime || fail "runtime setup"
build_rsync_filters
scan_images "${TEST_ROOT}/source" || fail "image scan"
[[ "$SCAN_COUNT" == "2" ]] || fail "expected two visible images, found ${SCAN_COUNT}"

run_rsync_copy \
  "${TEST_ROOT}/source" \
  "${TEST_ROOT}/destination" \
  "${TEST_ROOT}/rsync.log" || fail "rsync execution"
count_rsync_files "${TEST_ROOT}/rsync.log"

[[ "$RSYNC_EXIT_CODE" == "0" ]] || fail "rsync returned ${RSYNC_EXIT_CODE}"
[[ "$COPIED_COUNT" == "2" ]] || fail "expected two copied images, found ${COPIED_COUNT}"
verify_import "${TEST_ROOT}/source" "${TEST_ROOT}/destination" ||
  fail "size and count verification"
[[ "$VERIFIED_COUNT" == "2" ]] || fail "expected two verified images"

verify_checksums \
  "${TEST_ROOT}/source" \
  "${TEST_ROOT}/destination" \
  "${TEST_ROOT}/checksum.log" || fail "checksum verification"

[[ ! -e "${TEST_ROOT}/destination/100CAMERA/notes.txt" ]] ||
  fail "non-image file was copied"
[[ ! -e "${TEST_ROOT}/destination/.hidden/IMAGE_9999.JPG" ]] ||
  fail "hidden image was copied"

CAPTURE_DATE="2026-01-02"
CAMERA_MODEL='Example "Camera"'
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

print "Smoke test passed."
