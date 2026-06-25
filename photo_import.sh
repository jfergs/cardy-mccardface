#!/bin/zsh
#
# Automatically import camera-card images into a date-based photo archive.
# Intended to run as a per-user launchd LaunchAgent on macOS.

###############################################################################
# Configuration
###############################################################################

DESTINATION_ROOT="/Volumes/PhotoNAS/Photos"
AUTO_EJECT=true
SUPPORTED_EXTENSIONS=(CR3 CR2 NEF ARW RAF ORF RW2 DNG JPG JPEG HEIC PNG TIF TIFF)
LOGFILE="${HOME}/Library/Logs/CardyMcCardface.log"
DRY_RUN=false

# Optional production controls.
CHECKSUM_VERIFY=false
EXCLUDED_VOLUMES=("/Volumes/PhotoNAS" "/Volumes/Macintosh HD")
MIN_CARD_SIZE_GB=0
MAX_LOG_BYTES=10485760
LOG_BACKUPS=5
RUNTIME_ROOT="${TMPDIR:-/tmp}/com.cardymccardface.photoimporter.${UID}"
LOCK_ROOT="${RUNTIME_ROOT}/locks"

###############################################################################
# Runtime setup
###############################################################################

setopt PIPE_FAIL
setopt EXTENDED_GLOB
setopt NO_NOMATCH

typeset -a ACTIVE_LOCKS
typeset -a RSYNC_FILTER_ARGS
typeset EXIFTOOL_PATH=""

###############################################################################
# General helpers
###############################################################################

timestamp() {
  command date '+%Y-%m-%d %H:%M:%S%z'
}

iso_timestamp() {
  local raw
  raw="$(command date '+%Y-%m-%dT%H:%M:%S%z')"
  print -r -- "${raw[1,-3]}:${raw[-2,-1]}"
}

log() {
  local level="$1"
  shift
  local line
  line="$(timestamp) [$level] $*"
  print -r -- "$line" >> "$LOGFILE"

  if [[ -t 2 ]]; then
    case "$level" in
      ERROR) print -Pru2 -- "%F{red}${line}%f" ;;
      WARN)  print -Pru2 -- "%F{yellow}${line}%f" ;;
      INFO)  print -Pru2 -- "%F{green}${line}%f" ;;
      *)     print -ru2 -- "$line" ;;
    esac
  fi
}

notify() {
  local title="$1"
  local message="$2"

  /usr/bin/osascript - "$title" "$message" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

bool_is_true() {
  [[ "${1:l}" == "true" || "$1" == "1" || "${1:l}" == "yes" ]]
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  print -r -- "$value"
}

sanitize_component() {
  local value="$1"
  value="${value//[^A-Za-z0-9_.-]/_}"
  [[ -n "$value" ]] || value="volume"
  print -r -- "$value"
}

rotate_logs() {
  local size index

  [[ -f "$LOGFILE" ]] || return 0
  size="$(/usr/bin/stat -f '%z' "$LOGFILE" 2>/dev/null || print 0)"
  (( size >= MAX_LOG_BYTES )) || return 0

  if (( LOG_BACKUPS <= 0 )); then
    : > "$LOGFILE"
    return 0
  fi

  command rm -f "${LOGFILE}.${LOG_BACKUPS}"
  for (( index = LOG_BACKUPS - 1; index >= 1; index-- )); do
    [[ -f "${LOGFILE}.${index}" ]] &&
      command mv -f "${LOGFILE}.${index}" "${LOGFILE}.$(( index + 1 ))"
  done
  command mv -f "$LOGFILE" "${LOGFILE}.1"
  : > "$LOGFILE"
}

cleanup() {
  local lock_dir
  for lock_dir in "${ACTIVE_LOCKS[@]}"; do
    command rm -f "${lock_dir}/pid" 2>/dev/null
    command rmdir "$lock_dir" 2>/dev/null
  done
}

prepare_runtime() {
  local owner

  if [[ -L "$RUNTIME_ROOT" ]]; then
    print -ru2 -- "Unsafe runtime path is a symbolic link: $RUNTIME_ROOT"
    return 1
  fi

  if [[ -e "$RUNTIME_ROOT" && ! -d "$RUNTIME_ROOT" ]]; then
    print -ru2 -- "Unsafe runtime path is not a directory: $RUNTIME_ROOT"
    return 1
  fi

  command mkdir -p "$RUNTIME_ROOT" "$LOCK_ROOT" || return 1
  owner="$(/usr/bin/stat -f '%u' "$RUNTIME_ROOT" 2>/dev/null || print -1)"
  if [[ "$owner" != "$UID" ]]; then
    print -ru2 -- "Runtime directory is not owned by the current user: $RUNTIME_ROOT"
    return 1
  fi

  command chmod 700 "$RUNTIME_ROOT" "$LOCK_ROOT" || return 1
}

handle_signal() {
  log WARN "Importer interrupted by signal"
  exit 130
}

trap cleanup EXIT
trap handle_signal INT TERM HUP

###############################################################################
# Volume and lock handling
###############################################################################

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null
}

volume_is_excluded() {
  local volume="$1"
  local excluded
  for excluded in "${EXCLUDED_VOLUMES[@]}"; do
    [[ "$volume" == "$excluded" ]] && return 0
  done
  return 1
}

volume_info() {
  local volume="$1"
  local plist="$2"
  /usr/sbin/diskutil info -plist "$volume" > "$plist" 2>/dev/null
}

volume_is_removable() {
  local plist="$1"
  local removable

  removable="$(plist_value "$plist" Removable)"
  bool_is_true "$removable"
}

volume_meets_size_threshold() {
  local plist="$1"
  local bytes minimum_bytes

  (( MIN_CARD_SIZE_GB <= 0 )) && return 0
  bytes="$(plist_value "$plist" TotalSize)"
  [[ "$bytes" =~ ^[0-9]+$ ]] || return 1
  minimum_bytes=$(( MIN_CARD_SIZE_GB * 1024 * 1024 * 1024 ))
  (( bytes >= minimum_bytes ))
}

acquire_lock() {
  local identifier="$1"
  local safe_identifier lock_dir existing_pid

  safe_identifier="$(sanitize_component "$identifier")"
  lock_dir="${LOCK_ROOT}.${safe_identifier}.lock"

  if command mkdir "$lock_dir" 2>/dev/null; then
    print -r -- "$$" > "${lock_dir}/pid"
    ACTIVE_LOCKS+=("$lock_dir")
    REPLY="$lock_dir"
    return 0
  fi

  existing_pid=""
  [[ -r "${lock_dir}/pid" ]] && read -r existing_pid < "${lock_dir}/pid"
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    return 1
  fi

  # Remove a stale lock left by a crash or forced shutdown, then retry once.
  command rm -f "${lock_dir}/pid" 2>/dev/null
  command rmdir "$lock_dir" 2>/dev/null
  if command mkdir "$lock_dir" 2>/dev/null; then
    print -r -- "$$" > "${lock_dir}/pid"
    ACTIVE_LOCKS+=("$lock_dir")
    REPLY="$lock_dir"
    return 0
  fi

  return 1
}

release_lock() {
  local lock_dir="$1"
  local -a retained_locks
  local active

  command rm -f "${lock_dir}/pid" 2>/dev/null
  command rmdir "$lock_dir" 2>/dev/null

  for active in "${ACTIVE_LOCKS[@]}"; do
    [[ "$active" != "$lock_dir" ]] && retained_locks+=("$active")
  done
  ACTIVE_LOCKS=("${retained_locks[@]}")
}

###############################################################################
# Image discovery and metadata
###############################################################################

is_supported_image() {
  local path="$1"
  local name="${path:t}"
  local extension

  [[ "$name" == .* ]] && return 1
  [[ "$name" == *.* ]] || return 1
  extension="${name:e:u}"
  (( ${SUPPORTED_EXTENSIONS[(Ie)$extension]} > 0 ))
}

find_dcim_root() {
  local volume="$1"
  local candidate

  for candidate in "$volume"/*(N-/); do
    if [[ "${candidate:t:u}" == "DCIM" ]]; then
      REPLY="$candidate"
      return 0
    fi
  done
  return 1
}

scan_images() {
  local source_root="$1"
  local file
  local count=0
  local bytes=0
  local first=""
  local file_size

  while IFS= read -r -d $'\0' file; do
    is_supported_image "$file" || continue
    (( count++ ))
    [[ -n "$first" ]] || first="$file"
    file_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print 0)"
    [[ "$file_size" =~ ^[0-9]+$ ]] && (( bytes += file_size ))
  done < <(/usr/bin/find "$source_root" -type d -name '.*' -prune -o -type f -print0 2>/dev/null)

  SCAN_COUNT="$count"
  SCAN_BYTES="$bytes"
  SCAN_FIRST="$first"
  (( count > 0 ))
}

normalize_capture_date() {
  local value="$1"

  if [[ "$value" =~ ([0-9]{4})[:-]([0-9]{2})[:-]([0-9]{2}) ]]; then
    REPLY="${match[1]}-${match[2]}-${match[3]}"
    return 0
  fi
  return 1
}

metadata_value_exiftool() {
  local tag="$1"
  local file="$2"
  "$EXIFTOOL_PATH" -s3 "-${tag}" "$file" 2>/dev/null | /usr/bin/head -n 1
}

determine_capture_metadata() {
  local first_image="$1"
  local value=""
  local model=""

  if [[ -n "$EXIFTOOL_PATH" ]]; then
    value="$(metadata_value_exiftool DateTimeOriginal "$first_image")"
    if ! normalize_capture_date "$value"; then
      value="$(metadata_value_exiftool CreateDate "$first_image")"
      normalize_capture_date "$value" || REPLY=""
    fi
    model="$(metadata_value_exiftool Model "$first_image")"
  else
    value="$(/usr/bin/mdls -raw -name kMDItemContentCreationDate "$first_image" 2>/dev/null)"
    normalize_capture_date "$value" || REPLY=""
    model="$(/usr/bin/mdls -raw -name kMDItemAcquisitionModel "$first_image" 2>/dev/null)"
    [[ "$model" == "(null)" ]] && model=""
  fi

  CAPTURE_DATE="$REPLY"
  CAMERA_MODEL="$model"

  if [[ -z "$CAPTURE_DATE" ]]; then
    CAPTURE_DATE="$(/usr/bin/stat -f '%SB' -t '%Y-%m-%d' "$first_image" 2>/dev/null)"
  fi
  [[ "$CAPTURE_DATE" == [0-9]##-[0-9][0-9]-[0-9][0-9] ]] ||
    CAPTURE_DATE="$(command date '+%Y-%m-%d')"
}

build_rsync_filters() {
  local extension pattern character lower upper

  RSYNC_FILTER_ARGS=("--exclude=.*" "--include=*/")
  for extension in "${SUPPORTED_EXTENSIONS[@]}"; do
    pattern="*."
    for character in ${(s::)extension}; do
      if [[ "$character" == [[:alpha:]] ]]; then
        lower="${character:l}"
        upper="${character:u}"
        pattern+="[${lower}${upper}]"
      else
        pattern+="$character"
      fi
    done
    RSYNC_FILTER_ARGS+=("--include=${pattern}")
  done
  RSYNC_FILTER_ARGS+=("--exclude=*")
}

###############################################################################
# Copying and verification
###############################################################################

count_rsync_files() {
  local output_file="$1"
  local line itemized length name
  local count=0
  local bytes=0

  while IFS= read -r line; do
    [[ "$line" == PHOTOIMPORT\|* ]] || continue
    itemized="${${(s:|:)line}[2]}"
    length="${${(s:|:)line}[3]}"
    name="${${(s:|:)line}[4]}"
    [[ "$itemized" == '>f'* ]] || continue
    [[ -n "$name" ]] || continue
    (( count++ ))
    [[ "$length" =~ ^[0-9]+$ ]] && (( bytes += length ))
  done < "$output_file"

  COPIED_COUNT="$count"
  COPIED_BYTES="$bytes"
}

run_rsync_copy() {
  local source_root="$1"
  local destination="$2"
  local output_file="$3"
  local -a options
  local -a statuses

  options=(
    -rtp
    --ignore-existing
    --update
    --partial
    --partial-dir=.photoimport-partial
    --itemize-changes
    "--out-format=PHOTOIMPORT|%i|%l|%n"
    --progress
  )
  /usr/bin/rsync "${options[@]}" "${RSYNC_FILTER_ARGS[@]}" \
    "${source_root}/" "${destination}/" 2>&1 |
    /usr/bin/tee -a "$LOGFILE" "$output_file"
  statuses=("${pipestatus[@]}")
  RSYNC_EXIT_CODE="${statuses[1]:-1}"
}

plan_dry_run() {
  local source_root="$1"
  local destination="$2"
  local file relative target file_size
  local count=0
  local bytes=0

  while IFS= read -r -d $'\0' file; do
    is_supported_image "$file" || continue
    relative="${file#"${source_root}/"}"
    target="${destination}/${relative}"
    [[ -e "$target" ]] && continue

    (( count++ ))
    file_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print 0)"
    [[ "$file_size" =~ ^[0-9]+$ ]] && (( bytes += file_size ))
    log INFO "Dry run would copy: $file -> $target"
  done < <(/usr/bin/find "$source_root" -type d -name '.*' -prune -o -type f -print0 2>/dev/null)

  COPIED_COUNT="$count"
  COPIED_BYTES="$bytes"
  RSYNC_EXIT_CODE=0
}

verify_import() {
  local source_root="$1"
  local destination="$2"
  local file relative target source_size target_size
  local verified=0

  while IFS= read -r -d $'\0' file; do
    is_supported_image "$file" || continue
    relative="${file#"${source_root}/"}"
    target="${destination}/${relative}"
    [[ -f "$target" ]] || continue

    source_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print -1)"
    target_size="$(/usr/bin/stat -f '%z' "$target" 2>/dev/null || print -2)"
    [[ "$source_size" == "$target_size" ]] && (( verified++ ))
  done < <(/usr/bin/find "$source_root" -type d -name '.*' -prune -o -type f -print0 2>/dev/null)

  VERIFIED_COUNT="$verified"
  (( verified == SCAN_COUNT ))
}

verify_checksums() {
  local source_root="$1"
  local destination="$2"
  local output_file="$3"
  local line
  local -a statuses

  /usr/bin/rsync -rtpcn --itemize-changes "--out-format=%i|%n" \
    "${RSYNC_FILTER_ARGS[@]}" "${source_root}/" "${destination}/" \
    > "$output_file" 2>&1
  statuses=("${pipestatus[@]}")
  (( ${statuses[1]:-1} == 0 )) || return 1

  while IFS= read -r line; do
    [[ "$line" == '>f'* ]] && return 1
  done < "$output_file"
  return 0
}

write_sidecar() {
  local destination="$1"
  local volume_name="$2"
  local imported_at="$3"
  local elapsed="$4"
  local safe_volume sidecar temp_sidecar

  safe_volume="$(sanitize_component "$volume_name")"
  sidecar="${destination}/photo-import-${imported_at//[:+]/-}-${safe_volume}.json"
  temp_sidecar="${sidecar}.tmp.$$"

  {
    print -r -- "{"
    print -r -- "  \"imported_at\": \"$(json_escape "$imported_at")\","
    print -r -- "  \"camera\": \"$(json_escape "${CAMERA_MODEL:-Unknown}")\","
    print -r -- "  \"capture_date\": \"$(json_escape "$CAPTURE_DATE")\","
    print -r -- "  \"source_volume\": \"$(json_escape "$volume_name")\","
    print -r -- "  \"files\": ${SCAN_COUNT},"
    print -r -- "  \"bytes\": ${SCAN_BYTES},"
    print -r -- "  \"import_duration_seconds\": ${elapsed},"
    print -r -- "  \"verified\": true"
    print -r -- "}"
  } > "$temp_sidecar"

  command mv -f "$temp_sidecar" "$sidecar"
  log INFO "Sidecar written: $sidecar"
}

eject_volume() {
  local volume="$1"
  if /usr/sbin/diskutil eject "$volume" >> "$LOGFILE" 2>&1; then
    log INFO "Ejected source volume: $volume"
  else
    log WARN "Import succeeded, but eject failed for: $volume"
    notify "Photo import warning" "Import succeeded, but ${volume:t} could not be ejected."
  fi
}

###############################################################################
# Per-volume import workflow
###############################################################################

process_volume() {
  local volume="$1"
  local info_file="${RUNTIME_ROOT}/volume-info.$$.$RANDOM.plist"
  local device_identifier source_root volume_name year destination
  local lock_dir rsync_output checksum_output
  local started_at elapsed imported_at speed_mib
  local verification_result="failed"

  SCAN_COUNT=0
  SCAN_BYTES=0
  SCAN_FIRST=""
  COPIED_COUNT=0
  COPIED_BYTES=0
  VERIFIED_COUNT=0
  RSYNC_EXIT_CODE=1

  volume_is_excluded "$volume" && return 0
  [[ -d "$volume" ]] || return 0

  if ! volume_info "$volume" "$info_file"; then
    command rm -f "$info_file"
    return 0
  fi

  if ! volume_is_removable "$info_file"; then
    command rm -f "$info_file"
    return 0
  fi

  if ! volume_meets_size_threshold "$info_file"; then
    log INFO "Ignoring removable volume below size threshold: $volume"
    command rm -f "$info_file"
    return 0
  fi

  device_identifier="$(plist_value "$info_file" DeviceIdentifier)"
  command rm -f "$info_file"
  [[ -n "$device_identifier" ]] || device_identifier="${volume:t}"

  if find_dcim_root "$volume"; then
    source_root="$REPLY"
  else
    source_root="$volume"
  fi

  if ! scan_images "$source_root"; then
    log INFO "Ignoring removable volume with no supported images: $volume"
    return 0
  fi

  if ! acquire_lock "$device_identifier"; then
    log INFO "Import already active; ignoring duplicate event for: $volume"
    return 0
  fi
  lock_dir="$REPLY"

  volume_name="${volume:t}"
  determine_capture_metadata "$SCAN_FIRST"
  year="${CAPTURE_DATE[1,4]}"
  destination="${DESTINATION_ROOT}/${year}/${CAPTURE_DATE}"
  started_at=$SECONDS
  imported_at="$(iso_timestamp)"
  rsync_output="${RUNTIME_ROOT}/rsync.$$.$RANDOM.log"
  checksum_output="${RUNTIME_ROOT}/checksum.$$.$RANDOM.log"

  log INFO "Import started: source=$volume destination=$destination files=$SCAN_COUNT bytes=$SCAN_BYTES"
  notify "Import started" "${SCAN_COUNT} photos from ${volume_name} to ${destination}"

  if [[ ! -d "$DESTINATION_ROOT" ]]; then
    log ERROR "Destination root is unavailable: $DESTINATION_ROOT"
    notify "Import failed" "NAS destination is unavailable. ${volume_name} was left mounted."
    release_lock "$lock_dir"
    return 1
  fi

  if bool_is_true "$DRY_RUN"; then
    plan_dry_run "$source_root" "$destination"
    elapsed=$(( SECONDS - started_at ))
    (( elapsed < 1 )) && elapsed=1
    speed_mib=$(( COPIED_BYTES / elapsed / 1024 / 1024 ))
    log INFO "Dry run complete: source=$volume destination=$destination would_copy=$COPIED_COUNT elapsed_seconds=$elapsed rsync_exit=$RSYNC_EXIT_CODE estimated_mib_per_second=$speed_mib verification=not_run"
    notify "Photo import dry run" "Would copy ${COPIED_COUNT} photos to ${destination}"
    release_lock "$lock_dir"
    return 0
  fi

  if ! command mkdir -p "$destination"; then
    log ERROR "Could not create destination: $destination"
    notify "Import failed" "Could not create ${destination}. ${volume_name} was left mounted."
    release_lock "$lock_dir"
    return 1
  fi

  run_rsync_copy "$source_root" "$destination" "$rsync_output"
  count_rsync_files "$rsync_output"
  command rm -f "$rsync_output"
  elapsed=$(( SECONDS - started_at ))
  (( elapsed < 1 )) && elapsed=1
  speed_mib=$(( COPIED_BYTES / elapsed / 1024 / 1024 ))

  if (( RSYNC_EXIT_CODE == 0 )) && verify_import "$source_root" "$destination"; then
    if bool_is_true "$CHECKSUM_VERIFY"; then
      if verify_checksums "$source_root" "$destination" "$checksum_output"; then
        verification_result="passed (size, count, checksum)"
      else
        verification_result="failed (checksum)"
      fi
    else
      verification_result="passed (size and count)"
    fi
  else
    verification_result="failed (rsync, size, or count)"
  fi
  command rm -f "$checksum_output"

  if [[ "$verification_result" == passed* ]]; then
    write_sidecar "$destination" "$volume_name" "$imported_at" "$elapsed"
    log INFO "Import complete: source=$volume destination=$destination copied=$COPIED_COUNT source_files=$SCAN_COUNT verified_files=$VERIFIED_COUNT elapsed_seconds=$elapsed rsync_exit=$RSYNC_EXIT_CODE speed_mib_per_second=$speed_mib verification=$verification_result"
    notify "Import complete" "${SCAN_COUNT} photos verified in ${destination}"
    bool_is_true "$AUTO_EJECT" && eject_volume "$volume"
    release_lock "$lock_dir"
    return 0
  fi

  log ERROR "Import failed: source=$volume destination=$destination copied=$COPIED_COUNT source_files=$SCAN_COUNT verified_files=${VERIFIED_COUNT:-0} elapsed_seconds=$elapsed rsync_exit=$RSYNC_EXIT_CODE speed_mib_per_second=$speed_mib verification=$verification_result"
  notify "Import failed" "Verified ${VERIFIED_COUNT:-0} of ${SCAN_COUNT} photos. ${volume_name} was left mounted."
  release_lock "$lock_dir"
  return 1
}

###############################################################################
# Main
###############################################################################

main() {
  local volume
  local overall_status=0

  command mkdir -p "${LOGFILE:h}"
  [[ -e "$LOGFILE" ]] || : > "$LOGFILE"
  command chmod 600 "$LOGFILE" 2>/dev/null || true
  prepare_runtime || return 1
  rotate_logs
  build_rsync_filters

  if (( $+commands[exiftool] )); then
    EXIFTOOL_PATH="${commands[exiftool]}"
  elif [[ -x /opt/homebrew/bin/exiftool ]]; then
    EXIFTOOL_PATH="/opt/homebrew/bin/exiftool"
  elif [[ -x /usr/local/bin/exiftool ]]; then
    EXIFTOOL_PATH="/usr/local/bin/exiftool"
  fi

  if [[ -n "$EXIFTOOL_PATH" ]]; then
    log INFO "Using exiftool for capture metadata: $EXIFTOOL_PATH"
  else
    log INFO "exiftool not found; using mdls and file creation dates"
  fi

  for volume in /Volumes/*(N-/); do
    process_volume "$volume" || overall_status=1
  done

  return "$overall_status"
}

if ! bool_is_true "${PHOTO_IMPORTER_SOURCE_ONLY:-false}"; then
  main "$@"
fi
