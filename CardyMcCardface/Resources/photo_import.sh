#!/bin/zsh
#
# Automatically import camera-card images into a date-based photo archive.
# Intended to run from the Cardy McCardface macOS app.

###############################################################################
# Configuration
###############################################################################

DESTINATION_ROOT="${HOME}/Pictures/CardyMcCardface Imports"
AUTO_EJECT=false
SUPPORTED_EXTENSIONS=(CR3 CR2 NEF ARW RAF ORF RW2 DNG JPG JPEG HEIC PNG TIF TIFF)
PHOTO_EXTENSIONS=(CR3 CR2 NEF ARW RAF ORF RW2 DNG JPG JPEG HEIC PNG TIF TIFF)
VIDEO_EXTENSIONS=(MOV MP4 MXF MTS M2TS R3D BRAW CRM)
AUDIO_EXTENSIONS=(WAV AIFF AIF MP3)
LOGFILE="${HOME}/Library/Logs/CardyMcCardface.log"
DRY_RUN=true
NOTIFICATIONS_ENABLED=true

# Optional production controls.
CHECKSUM_VERIFY=false
EXCLUDED_VOLUMES=("/Volumes/PhotoNAS" "/Volumes/Macintosh HD")
MIN_CARD_SIZE_GB=0
WORKFLOW_PRESET="personal-photo"
MEDIA_MODE="photos-only"
ORGANIZATION_MODE="daily"
DATE_FOLDER_STYLE="year-date"
SHOOT_FOLDER_STYLE="time-volume"
INGEST_VILLAGE_MODE=false
STATION_NAME="$(/bin/hostname -s 2>/dev/null || print CardyStation)"
OPERATOR_NAME=""
SHARED_STATUS_ENABLED=false
SHARED_MANIFEST_ENABLED=false
SHARED_LOCKS_ENABLED=false
SHARED_STATUS_DIR=""
SHARED_MANIFEST_DIR=""
SHARED_LOCK_DIR=""
MIN_FREE_SPACE_GB=0
MAX_LOG_BYTES=10485760
LOG_BACKUPS=5
CONFIG_FILE="${CARDY_CONFIG_FILE:-${HOME}/Library/Application Support/CardyMcCardface/config.plist}"
STATUS_FILE="${CARDY_STATUS_FILE:-${HOME}/Library/Application Support/CardyMcCardface/status.plist}"
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
typeset -a DATE_KEYS
typeset -A DATE_MANIFESTS
typeset -A DATE_COUNTS
typeset -A DATE_BYTES
typeset -A DATE_TIMES
typeset -A DATE_CAMERAS
typeset -A DATE_PHOTO_COUNTS
typeset -A DATE_VIDEO_COUNTS
typeset -A DATE_AUDIO_COUNTS
typeset EXIFTOOL_PATH=""
typeset MDLS_ENABLED=true
typeset -a ACTIVE_SHARED_LOCKS
typeset MEDIA_PHOTO_COUNT=0
typeset MEDIA_VIDEO_COUNT=0
typeset MEDIA_AUDIO_COUNT=0

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
  local subtitle="${3:-Cardy McCardface}"

  bool_is_true "$NOTIFICATIONS_ENABLED" || return 0

  /usr/bin/osascript - "$title" "$message" "$subtitle" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  display notification (item 2 of argv) with title (item 1 of argv) subtitle (item 3 of argv)
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

shared_path_default() {
  local leaf="$1"
  REPLY="${DESTINATION_ROOT}/${leaf}"
}

write_status() {
  local state="$1"
  local message="$2"
  local file_count="${3:-0}"
  local destination="${4:-}"
  local status_dir="${STATUS_FILE:h}"
  local temporary="${status_dir}/status.plist.tmp.$$"

  command mkdir -p "$status_dir" || return 1
  command chmod 700 "$status_dir" 2>/dev/null || true
  /usr/bin/plutil -create xml1 "$temporary" || return 1
  /usr/bin/plutil -insert state -string "$state" "$temporary"
  /usr/bin/plutil -insert message -string "$message" "$temporary"
  /usr/bin/plutil -insert fileCount -integer "$file_count" "$temporary"
  /usr/bin/plutil -insert destination -string "$destination" "$temporary"
  /usr/bin/plutil -insert updatedAt -string "$(iso_timestamp)" "$temporary"
  command chmod 600 "$temporary"
  command mv -f "$temporary" "$STATUS_FILE"
}

write_shared_status() {
  local state="$1"
  local message="$2"
  local file_count="${3:-0}"
  local destination="${4:-}"
  local source_volume="${5:-}"
  local directory temporary status_file safe_station

  bool_is_true "$INGEST_VILLAGE_MODE" || return 0
  bool_is_true "$SHARED_STATUS_ENABLED" || return 0

  directory="$SHARED_STATUS_DIR"
  [[ -n "$directory" ]] || {
    shared_path_default ".cardy-status"
    directory="$REPLY"
  }

  safe_station="$(sanitize_component "$STATION_NAME")"
  status_file="${directory}/${safe_station}.json"
  temporary="${status_file}.tmp.$$"

  command mkdir -p "$directory" || return 1
  {
    print -r -- "{"
    print -r -- "  \"updated_at\": \"$(json_escape "$(iso_timestamp)")\","
    print -r -- "  \"state\": \"$(json_escape "$state")\","
    print -r -- "  \"message\": \"$(json_escape "$message")\","
    print -r -- "  \"station_name\": \"$(json_escape "$STATION_NAME")\","
    print -r -- "  \"hostname\": \"$(json_escape "$(/bin/hostname 2>/dev/null || print unknown)")\","
    print -r -- "  \"operator\": \"$(json_escape "$OPERATOR_NAME")\","
    print -r -- "  \"source_volume\": \"$(json_escape "$source_volume")\","
    print -r -- "  \"destination\": \"$(json_escape "$destination")\","
    print -r -- "  \"file_count\": ${file_count}"
    print -r -- "}"
  } > "$temporary"
  command mv -f "$temporary" "$status_file"
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
  for lock_dir in "${ACTIVE_SHARED_LOCKS[@]}"; do
    command rm -f "${lock_dir}/owner" 2>/dev/null
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
  local output

  if output="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null)"; then
    print -r -- "$output"
  fi
}

config_value() {
  local key="$1"
  plist_value "$CONFIG_FILE" "$key"
}

load_configuration() {
  local value owner

  [[ -f "$CONFIG_FILE" ]] || {
    log ERROR "Configuration plist is missing: $CONFIG_FILE"
    return 1
  }
  [[ ! -L "$CONFIG_FILE" ]] || {
    log ERROR "Configuration plist must not be a symbolic link: $CONFIG_FILE"
    return 1
  }
  owner="$(/usr/bin/stat -f '%u' "$CONFIG_FILE" 2>/dev/null || print -1)"
  [[ "$owner" == "$UID" ]] || {
    log ERROR "Configuration plist is not owned by the current user: $CONFIG_FILE"
    return 1
  }
  /usr/bin/plutil -lint "$CONFIG_FILE" >/dev/null 2>&1 || {
    log ERROR "Configuration plist is invalid: $CONFIG_FILE"
    return 1
  }

  value="$(config_value destinationRoot)"
  [[ -n "$value" && "$value" == /* && "$value" != *$'\n'* &&
    "$value" != "/" && "$value" != "/Volumes" ]] || {
    log ERROR "Configuration destinationRoot must be an absolute dedicated folder"
    return 1
  }
  DESTINATION_ROOT="${value%/}"

  value="$(config_value organizationMode)"
  case "$value" in
    daily|shoots) ORGANIZATION_MODE="$value" ;;
    *) log ERROR "Unsupported organizationMode in configuration: $value"; return 1 ;;
  esac

  value="$(config_value dateFolderStyle)"
  case "$value" in
    year-date|date-only|nested-date) DATE_FOLDER_STYLE="$value" ;;
    *) log ERROR "Unsupported dateFolderStyle in configuration: $value"; return 1 ;;
  esac

  value="$(config_value shootFolderStyle)"
  case "$value" in
    time-volume|time-camera|time-only) SHOOT_FOLDER_STYLE="$value" ;;
    *) log ERROR "Unsupported shootFolderStyle in configuration: $value"; return 1 ;;
  esac

  value="$(config_value autoEject)"
  case "$value" in
    true|false) AUTO_EJECT="$value" ;;
    *) log ERROR "autoEject must be a boolean"; return 1 ;;
  esac
  value="$(config_value checksumVerify)"
  case "$value" in
    true|false) CHECKSUM_VERIFY="$value" ;;
    *) log ERROR "checksumVerify must be a boolean"; return 1 ;;
  esac
  value="$(config_value dryRun)"
  case "$value" in
    true|false) DRY_RUN="$value" ;;
    *) log ERROR "dryRun must be a boolean"; return 1 ;;
  esac
  value="$(config_value notificationsEnabled)"
  case "$value" in
    true|false) NOTIFICATIONS_ENABLED="$value" ;;
    "") NOTIFICATIONS_ENABLED=true ;;
    *) log ERROR "notificationsEnabled must be a boolean"; return 1 ;;
  esac
  value="$(config_value minCardSizeGB)"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    MIN_CARD_SIZE_GB="$value"
  else
    log ERROR "minCardSizeGB must be a non-negative integer"
    return 1
  fi

  value="$(config_value workflowPreset)"
  case "$value" in
    personal-photo|capture-one|adobe-photo|video-production|hybrid-production|ingest-village)
      WORKFLOW_PRESET="$value"
      ;;
    "") WORKFLOW_PRESET="personal-photo" ;;
    *) log ERROR "Unsupported workflowPreset in configuration: $value"; return 1 ;;
  esac
  value="$(config_value mediaMode)"
  case "$value" in
    photos-only|videos-only|photos-and-videos) MEDIA_MODE="$value" ;;
    "") MEDIA_MODE="photos-only" ;;
    *) log ERROR "Unsupported mediaMode in configuration: $value"; return 1 ;;
  esac

  value="$(config_value ingestVillageMode)"
  case "$value" in
    true|false) INGEST_VILLAGE_MODE="$value" ;;
    "") INGEST_VILLAGE_MODE=false ;;
    *) log ERROR "ingestVillageMode must be a boolean"; return 1 ;;
  esac
  value="$(config_value stationName)"
  [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] &&
    STATION_NAME="$value"
  value="$(config_value operatorName)"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] &&
    OPERATOR_NAME="$value"
  value="$(config_value sharedStatusEnabled)"
  case "$value" in
    true|false) SHARED_STATUS_ENABLED="$value" ;;
    "") SHARED_STATUS_ENABLED="$INGEST_VILLAGE_MODE" ;;
    *) log ERROR "sharedStatusEnabled must be a boolean"; return 1 ;;
  esac
  value="$(config_value sharedManifestEnabled)"
  case "$value" in
    true|false) SHARED_MANIFEST_ENABLED="$value" ;;
    "") SHARED_MANIFEST_ENABLED="$INGEST_VILLAGE_MODE" ;;
    *) log ERROR "sharedManifestEnabled must be a boolean"; return 1 ;;
  esac
  value="$(config_value sharedLocksEnabled)"
  case "$value" in
    true|false) SHARED_LOCKS_ENABLED="$value" ;;
    "") SHARED_LOCKS_ENABLED="$INGEST_VILLAGE_MODE" ;;
    *) log ERROR "sharedLocksEnabled must be a boolean"; return 1 ;;
  esac
  value="$(config_value sharedStatusDir)"
  [[ -n "$value" ]] && SHARED_STATUS_DIR="${value%/}"
  value="$(config_value sharedManifestDir)"
  [[ -n "$value" ]] && SHARED_MANIFEST_DIR="${value%/}"
  value="$(config_value sharedLockDir)"
  [[ -n "$value" ]] && SHARED_LOCK_DIR="${value%/}"
  value="$(config_value minFreeSpaceGB)"
  if [[ -z "$value" ]]; then
    MIN_FREE_SPACE_GB=0
  elif [[ "$value" =~ ^[0-9]+$ ]]; then
    MIN_FREE_SPACE_GB="$value"
  else
    log ERROR "minFreeSpaceGB must be a non-negative integer"
    return 1
  fi

  if bool_is_true "$INGEST_VILLAGE_MODE"; then
    WORKFLOW_PRESET="ingest-village"
    MEDIA_MODE="photos-and-videos"
    ORGANIZATION_MODE="shoots"
    CHECKSUM_VERIFY=true
    AUTO_EJECT=false
    [[ -n "$SHARED_STATUS_DIR" ]] || SHARED_STATUS_DIR="${DESTINATION_ROOT}/.cardy-status"
    [[ -n "$SHARED_MANIFEST_DIR" ]] || SHARED_MANIFEST_DIR="${DESTINATION_ROOT}/.cardy-imports"
    [[ -n "$SHARED_LOCK_DIR" ]] || SHARED_LOCK_DIR="${DESTINATION_ROOT}/.cardy-locks"
  fi
}

destination_volume_root() {
  local destination="$1"
  local relative volume_name

  [[ "$destination" == /Volumes/* ]] || return 1
  relative="${destination#/Volumes/}"
  volume_name="${relative%%/*}"
  [[ -n "$volume_name" ]] || return 1
  REPLY="/Volumes/${volume_name}"
}

volume_is_excluded() {
  local volume="$1"
  local excluded

  if destination_volume_root "$DESTINATION_ROOT" && [[ "$volume" == "$REPLY" ]]; then
    return 0
  fi

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

acquire_shared_lock() {
  local identifier="$1"
  local safe_identifier lock_dir owner_file stale_age now modified

  bool_is_true "$INGEST_VILLAGE_MODE" || { REPLY=""; return 0; }
  bool_is_true "$SHARED_LOCKS_ENABLED" || { REPLY=""; return 0; }

  [[ -n "$SHARED_LOCK_DIR" ]] || SHARED_LOCK_DIR="${DESTINATION_ROOT}/.cardy-locks"
  command mkdir -p "$SHARED_LOCK_DIR" || return 1

  safe_identifier="$(sanitize_component "$identifier")"
  lock_dir="${SHARED_LOCK_DIR}/${safe_identifier}.lock"
  owner_file="${lock_dir}/owner"

  if command mkdir "$lock_dir" 2>/dev/null; then
    {
      print -r -- "station=${STATION_NAME}"
      print -r -- "operator=${OPERATOR_NAME}"
      print -r -- "pid=$$"
      print -r -- "created_at=$(iso_timestamp)"
    } > "$owner_file"
    ACTIVE_SHARED_LOCKS+=("$lock_dir")
    REPLY="$lock_dir"
    return 0
  fi

  # Network locks are intentionally conservative. Only remove very old locks
  # that are likely abandoned by a crashed ingest station.
  now="$(command date '+%s')"
  modified="$(/usr/bin/stat -f '%m' "$lock_dir" 2>/dev/null || print "$now")"
  stale_age=$(( now - modified ))
  if (( stale_age > 86400 )); then
    log WARN "Removing stale shared lock older than 24h: $lock_dir"
    command rm -f "$owner_file" 2>/dev/null
    command rmdir "$lock_dir" 2>/dev/null
    if command mkdir "$lock_dir" 2>/dev/null; then
      print -r -- "station=${STATION_NAME}" > "$owner_file"
      ACTIVE_SHARED_LOCKS+=("$lock_dir")
      REPLY="$lock_dir"
      return 0
    fi
  fi

  return 1
}

release_shared_lock() {
  local lock_dir="$1"
  local -a retained_locks
  local active

  [[ -n "$lock_dir" ]] || return 0
  command rm -f "${lock_dir}/owner" 2>/dev/null
  command rmdir "$lock_dir" 2>/dev/null

  for active in "${ACTIVE_SHARED_LOCKS[@]}"; do
    [[ "$active" != "$lock_dir" ]] && retained_locks+=("$active")
  done
  ACTIVE_SHARED_LOCKS=("${retained_locks[@]}")
}

preflight_destination_root() {
  local test_dir test_file free_blocks block_size free_bytes minimum_bytes

  [[ "$DESTINATION_ROOT" == /* && "$DESTINATION_ROOT" != "/" &&
    "$DESTINATION_ROOT" != "/Volumes" ]] || {
    log ERROR "Destination root is not safe: $DESTINATION_ROOT"
    return 1
  }

  [[ -d "$DESTINATION_ROOT" ]] || {
    log ERROR "Destination root is unavailable: $DESTINATION_ROOT"
    return 1
  }

  test_dir="${DESTINATION_ROOT}/.cardy-preflight"
  test_file="${test_dir}/write-test.$$"
  command mkdir -p "$test_dir" || {
    log ERROR "Destination root is not writable: $DESTINATION_ROOT"
    return 1
  }
  print -r -- "$(iso_timestamp) ${STATION_NAME}" > "$test_file" || {
    log ERROR "Could not write destination preflight file: $test_file"
    return 1
  }
  command rm -f "$test_file"
  command rmdir "$test_dir" 2>/dev/null || true

  if (( MIN_FREE_SPACE_GB > 0 )); then
    free_blocks="$(/usr/bin/stat -f '%a' "$DESTINATION_ROOT" 2>/dev/null || print "")"
    block_size="$(/usr/bin/stat -f '%S' "$DESTINATION_ROOT" 2>/dev/null || print "")"
    [[ "$free_blocks" =~ ^[0-9]+$ && "$block_size" =~ ^[0-9]+$ ]] || {
      log ERROR "Could not determine free space for destination: $DESTINATION_ROOT"
      return 1
    }
    free_bytes=$(( free_blocks * block_size ))
    minimum_bytes=$(( MIN_FREE_SPACE_GB * 1024 * 1024 * 1024 ))
    if (( free_bytes < minimum_bytes )); then
      log ERROR "Destination free space below threshold: free_bytes=$free_bytes required_bytes=$minimum_bytes"
      return 1
    fi
  fi
}

###############################################################################
# Image discovery and metadata
###############################################################################

is_supported_image() {
  local path="$1"
  media_kind_for_path "$path" >/dev/null
}

media_kind_for_path() {
  local path="$1"
  local name="${path:t}"
  local extension

  [[ "$name" == .* ]] && return 1
  [[ "$name" == *.* ]] || return 1
  extension="${name:e:u}"
  if (( ${PHOTO_EXTENSIONS[(Ie)$extension]} > 0 )); then
    [[ "$MEDIA_MODE" == "videos-only" ]] && return 1
    REPLY="photo"
    return 0
  fi
  if (( ${VIDEO_EXTENSIONS[(Ie)$extension]} > 0 )); then
    [[ "$MEDIA_MODE" == "photos-only" ]] && return 1
    REPLY="video"
    return 0
  fi
  if (( ${AUDIO_EXTENSIONS[(Ie)$extension]} > 0 )); then
    [[ "$MEDIA_MODE" == "photos-only" ]] && return 1
    REPLY="audio"
    return 0
  fi
  return 1
}

metadata_supported_for_path() {
  local path="$1"
  media_kind_for_path "$path" || return 1
  [[ "$REPLY" == "photo" ]]
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

classify_images_by_date() {
  local source_root="$1"
  local file relative file_size manifest media_kind
  local total_count=0
  local total_bytes=0
  local first=""

  DATE_KEYS=()
  DATE_MANIFESTS=()
  DATE_COUNTS=()
  DATE_BYTES=()
  DATE_TIMES=()
  DATE_CAMERAS=()
  DATE_PHOTO_COUNTS=()
  DATE_VIDEO_COUNTS=()
  DATE_AUDIO_COUNTS=()
  MEDIA_PHOTO_COUNT=0
  MEDIA_VIDEO_COUNT=0
  MEDIA_AUDIO_COUNT=0

  while IFS= read -r -d $'\0' file; do
    media_kind_for_path "$file" || continue
    media_kind="$REPLY"
    if [[ "$file" == *$'\n'* || "$file" == *$'\r'* ]]; then
      log WARN "Skipping filename containing a line break: $file"
      continue
    fi

    if metadata_supported_for_path "$file"; then
      determine_capture_metadata "$file"
    else
      determine_capture_metadata_from_file "$file"
    fi
    relative="${file#"${source_root}/"}"
    [[ -n "$first" ]] || first="$relative"
    manifest="${DATE_MANIFESTS[$CAPTURE_DATE]:-}"
    if [[ -z "$manifest" ]]; then
      manifest="${RUNTIME_ROOT}/files-${CAPTURE_DATE}.$$.$RANDOM.txt"
      : > "$manifest"
      DATE_MANIFESTS[$CAPTURE_DATE]="$manifest"
      DATE_COUNTS[$CAPTURE_DATE]=0
      DATE_BYTES[$CAPTURE_DATE]=0
      DATE_TIMES[$CAPTURE_DATE]="$CAPTURE_TIME"
      DATE_CAMERAS[$CAPTURE_DATE]="$CAMERA_MODEL"
      DATE_PHOTO_COUNTS[$CAPTURE_DATE]=0
      DATE_VIDEO_COUNTS[$CAPTURE_DATE]=0
      DATE_AUDIO_COUNTS[$CAPTURE_DATE]=0
      DATE_KEYS+=("$CAPTURE_DATE")
    fi

    print -r -- "$relative" >> "$manifest"
    file_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print 0)"
    [[ "$file_size" =~ ^[0-9]+$ ]] || file_size=0
    DATE_COUNTS[$CAPTURE_DATE]=$(( DATE_COUNTS[$CAPTURE_DATE] + 1 ))
    DATE_BYTES[$CAPTURE_DATE]=$(( DATE_BYTES[$CAPTURE_DATE] + file_size ))
    case "$media_kind" in
      photo)
        DATE_PHOTO_COUNTS[$CAPTURE_DATE]=$(( DATE_PHOTO_COUNTS[$CAPTURE_DATE] + 1 ))
        (( MEDIA_PHOTO_COUNT++ ))
        ;;
      video)
        DATE_VIDEO_COUNTS[$CAPTURE_DATE]=$(( DATE_VIDEO_COUNTS[$CAPTURE_DATE] + 1 ))
        (( MEDIA_VIDEO_COUNT++ ))
        ;;
      audio)
        DATE_AUDIO_COUNTS[$CAPTURE_DATE]=$(( DATE_AUDIO_COUNTS[$CAPTURE_DATE] + 1 ))
        (( MEDIA_AUDIO_COUNT++ ))
        ;;
    esac
    (( total_count++ ))
    (( total_bytes += file_size ))
  done < <(/usr/bin/find "$source_root" -type d -name '.*' -prune -o -type f -print0 2>/dev/null)

  SCAN_COUNT="$total_count"
  SCAN_BYTES="$total_bytes"
  SCAN_FIRST="$first"
  (( total_count > 0 ))
}

remove_date_manifests() {
  local capture_date manifest
  for capture_date in "${DATE_KEYS[@]}"; do
    manifest="${DATE_MANIFESTS[$capture_date]:-}"
    [[ -n "$manifest" ]] && command rm -f "$manifest"
  done
}

normalize_capture_date() {
  local value="$1"
  local year current_year

  if [[ "$value" =~ ([0-9]{4})[:-]([0-9]{2})[:-]([0-9]{2}) ]]; then
    year="${match[1]}"
    current_year="$(command date '+%Y')"
    (( year >= 1980 && year <= current_year + 1 )) || return 1
    REPLY="${match[1]}-${match[2]}-${match[3]}"
    return 0
  fi
  return 1
}

normalize_capture_time() {
  local value="$1"

  if [[ "$value" =~ ([0-9]{2}):([0-9]{2}):([0-9]{2}) ]]; then
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
    if bool_is_true "$MDLS_ENABLED" &&
      value="$(/usr/bin/mdls -raw -name kMDItemContentCreationDate "$first_image" 2>/dev/null)"; then
      normalize_capture_date "$value" || REPLY=""
    else
      MDLS_ENABLED=false
      value=""
      REPLY=""
    fi
    if bool_is_true "$MDLS_ENABLED" &&
      model="$(/usr/bin/mdls -raw -name kMDItemAcquisitionModel "$first_image" 2>/dev/null)"; then
      :
    else
      model=""
    fi
    [[ "$model" == "(null)" || "$model" == *"could not find"* ]] && model=""
  fi

  CAPTURE_DATE="$REPLY"
  normalize_capture_time "$value" || REPLY=""
  CAPTURE_TIME="$REPLY"
  CAMERA_MODEL="$model"

  if [[ -z "$CAPTURE_DATE" ]]; then
    CAPTURE_DATE="$(/usr/bin/stat -f '%SB' -t '%Y-%m-%d' "$first_image" 2>/dev/null)"
  fi
  if [[ -z "$CAPTURE_TIME" ]]; then
    CAPTURE_TIME="$(/usr/bin/stat -f '%SB' -t '%H-%M-%S' "$first_image" 2>/dev/null)"
  fi
  [[ "$CAPTURE_DATE" == [0-9]##-[0-9][0-9]-[0-9][0-9] ]] ||
    CAPTURE_DATE="$(command date '+%Y-%m-%d')"
  [[ "$CAPTURE_TIME" == [0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
    CAPTURE_TIME="$(command date '+%H-%M-%S')"
}

determine_capture_metadata_from_file() {
  local file="$1"

  CAPTURE_DATE="$(/usr/bin/stat -f '%SB' -t '%Y-%m-%d' "$file" 2>/dev/null)"
  CAPTURE_TIME="$(/usr/bin/stat -f '%SB' -t '%H-%M-%S' "$file" 2>/dev/null)"
  CAMERA_MODEL=""
  [[ "$CAPTURE_DATE" == [0-9]##-[0-9][0-9]-[0-9][0-9] ]] ||
    CAPTURE_DATE="$(command date '+%Y-%m-%d')"
  [[ "$CAPTURE_TIME" == [0-9][0-9]-[0-9][0-9]-[0-9][0-9] ]] ||
    CAPTURE_TIME="$(command date '+%H-%M-%S')"
}

build_destination() {
  local volume_name="$1"
  local year="${CAPTURE_DATE[1,4]}"
  local month="${CAPTURE_DATE[6,7]}"
  local day="${CAPTURE_DATE[9,10]}"
  local relative shoot_suffix shoot_folder

  case "$DATE_FOLDER_STYLE" in
    year-date)   relative="${year}/${CAPTURE_DATE}" ;;
    date-only)   relative="${CAPTURE_DATE}" ;;
    nested-date) relative="${year}/${month}/${day}" ;;
    *) return 1 ;;
  esac

  if [[ "$ORGANIZATION_MODE" == "shoots" ]]; then
    case "$SHOOT_FOLDER_STYLE" in
      time-volume) shoot_suffix="$(sanitize_component "$volume_name")" ;;
      time-camera) shoot_suffix="$(sanitize_component "${CAMERA_MODEL:-Unknown_Camera}")" ;;
      time-only)   shoot_suffix="" ;;
      *) return 1 ;;
    esac

    shoot_folder="${CAPTURE_TIME}"
    [[ -n "$shoot_suffix" ]] && shoot_folder+="_${shoot_suffix}"
    relative+="/${shoot_folder}"
  fi

  REPLY="${DESTINATION_ROOT}/${relative}"
}

create_workflow_scaffold() {
  local destination="$1"

  case "$WORKFLOW_PRESET" in
    capture-one)
      command mkdir -p \
        "${destination}/Capture" \
        "${destination}/Selects" \
        "${destination}/Output" \
        "${destination}/Trash" \
        "${destination}/Cardy Import Reports"
      ;;
    adobe-photo)
      command mkdir -p \
        "${destination}/01_Photos" \
        "${destination}/02_Lightroom_Bridge" \
        "${destination}/03_Edits" \
        "${destination}/04_Exports" \
        "${destination}/05_Reports"
      ;;
    video-production)
      command mkdir -p \
        "${destination}/01_Media/Video" \
        "${destination}/01_Media/Audio" \
        "${destination}/02_Project_Files" \
        "${destination}/03_Proxies" \
        "${destination}/04_Exports" \
        "${destination}/05_Reports"
      ;;
    hybrid-production|ingest-village)
      command mkdir -p \
        "${destination}/01_Media/Photos" \
        "${destination}/01_Media/Video" \
        "${destination}/01_Media/Audio" \
        "${destination}/02_Capture_One" \
        "${destination}/03_Adobe" \
        "${destination}/04_Proxies" \
        "${destination}/05_Exports" \
        "${destination}/06_Reports"
      ;;
    *)
      return 0
      ;;
  esac
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

run_rsync_manifest() {
  local source_root="$1"
  local destination="$2"
  local manifest="$3"
  local output_file="$4"
  local -a options
  local -a statuses

  options=(
    -rtp
    --ignore-existing
    --update
    --partial
    --partial-dir=.photoimport-partial
    "--files-from=${manifest}"
    --itemize-changes
    "--out-format=PHOTOIMPORT|%i|%l|%n"
    --progress
  )
  /usr/bin/rsync "${options[@]}" \
    "${source_root}/" "${destination}/" 2>&1 |
    /usr/bin/tee -a "$LOGFILE" "$output_file"
  statuses=("${pipestatus[@]}")
  RSYNC_EXIT_CODE="${statuses[1]:-1}"
}

plan_dry_run_manifest() {
  local source_root="$1"
  local destination="$2"
  local manifest="$3"
  local file relative target file_size
  local count=0
  local bytes=0

  while IFS= read -r relative; do
    [[ -n "$relative" ]] || continue
    file="${source_root}/${relative}"
    target="${destination}/${relative}"
    [[ -e "$target" ]] && continue

    (( count++ ))
    file_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print 0)"
    [[ "$file_size" =~ ^[0-9]+$ ]] && (( bytes += file_size ))
    log INFO "Dry run would copy: $file -> $target"
  done < "$manifest"

  COPIED_COUNT="$count"
  COPIED_BYTES="$bytes"
  RSYNC_EXIT_CODE=0
}

verify_import_manifest() {
  local source_root="$1"
  local destination="$2"
  local manifest="$3"
  local expected_count="$4"
  local file relative target source_size target_size
  local verified=0

  while IFS= read -r relative; do
    [[ -n "$relative" ]] || continue
    file="${source_root}/${relative}"
    target="${destination}/${relative}"
    [[ -f "$target" ]] || continue

    source_size="$(/usr/bin/stat -f '%z' "$file" 2>/dev/null || print -1)"
    target_size="$(/usr/bin/stat -f '%z' "$target" 2>/dev/null || print -2)"
    [[ "$source_size" == "$target_size" ]] && (( verified++ ))
  done < "$manifest"

  VERIFIED_COUNT="$verified"
  (( verified == expected_count ))
}

verify_checksums_manifest() {
  local source_root="$1"
  local destination="$2"
  local manifest="$3"
  local output_file="$4"
  local line
  local -a statuses

  /usr/bin/rsync -rtpcn "--files-from=${manifest}" \
    --itemize-changes "--out-format=%i|%n" \
    "${source_root}/" "${destination}/" \
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
    print -r -- "  \"capture_time\": \"$(json_escape "$CAPTURE_TIME")\","
    print -r -- "  \"source_volume\": \"$(json_escape "$volume_name")\","
    print -r -- "  \"workflow_preset\": \"$(json_escape "$WORKFLOW_PRESET")\","
    print -r -- "  \"media_mode\": \"$(json_escape "$MEDIA_MODE")\","
    print -r -- "  \"organization_mode\": \"$(json_escape "$ORGANIZATION_MODE")\","
    print -r -- "  \"photo_files\": ${MEDIA_PHOTO_COUNT},"
    print -r -- "  \"video_files\": ${MEDIA_VIDEO_COUNT},"
    print -r -- "  \"audio_files\": ${MEDIA_AUDIO_COUNT},"
    print -r -- "  \"files\": ${SCAN_COUNT},"
    print -r -- "  \"bytes\": ${SCAN_BYTES},"
    print -r -- "  \"import_duration_seconds\": ${elapsed},"
    print -r -- "  \"verified\": true"
    print -r -- "}"
  } > "$temp_sidecar"

  command mv -f "$temp_sidecar" "$sidecar"
  log INFO "Sidecar written: $sidecar"
}

write_shared_import_manifest() {
  local state="$1"
  local volume_name="$2"
  local destination_root="$3"
  local imported_at="$4"
  local elapsed="$5"
  local source_files="$6"
  local copied_files="$7"
  local verified_files="$8"
  local source_bytes="$9"
  local copied_bytes="${10}"
  local verification="${11}"
  local safe_station safe_volume directory manifest temp_manifest

  bool_is_true "$INGEST_VILLAGE_MODE" || return 0
  bool_is_true "$SHARED_MANIFEST_ENABLED" || return 0

  directory="$SHARED_MANIFEST_DIR"
  [[ -n "$directory" ]] || {
    shared_path_default ".cardy-imports"
    directory="$REPLY"
  }

  command mkdir -p "$directory" || return 1
  safe_station="$(sanitize_component "$STATION_NAME")"
  safe_volume="$(sanitize_component "$volume_name")"
  manifest="${directory}/${imported_at//[:+]/-}_${safe_station}_${safe_volume}.json"
  temp_manifest="${manifest}.tmp.$$"

  {
    print -r -- "{"
    print -r -- "  \"imported_at\": \"$(json_escape "$imported_at")\","
    print -r -- "  \"state\": \"$(json_escape "$state")\","
    print -r -- "  \"station_name\": \"$(json_escape "$STATION_NAME")\","
    print -r -- "  \"hostname\": \"$(json_escape "$(/bin/hostname 2>/dev/null || print unknown)")\","
    print -r -- "  \"operator\": \"$(json_escape "$OPERATOR_NAME")\","
    print -r -- "  \"source_volume\": \"$(json_escape "$volume_name")\","
    print -r -- "  \"destination_root\": \"$(json_escape "$destination_root")\","
    print -r -- "  \"workflow_preset\": \"$(json_escape "$WORKFLOW_PRESET")\","
    print -r -- "  \"media_mode\": \"$(json_escape "$MEDIA_MODE")\","
    print -r -- "  \"organization_mode\": \"$(json_escape "$ORGANIZATION_MODE")\","
    print -r -- "  \"date_folder_style\": \"$(json_escape "$DATE_FOLDER_STYLE")\","
    print -r -- "  \"shoot_folder_style\": \"$(json_escape "$SHOOT_FOLDER_STYLE")\","
    print -r -- "  \"capture_dates\": ${#DATE_KEYS[@]},"
    print -r -- "  \"photo_files\": ${MEDIA_PHOTO_COUNT},"
    print -r -- "  \"video_files\": ${MEDIA_VIDEO_COUNT},"
    print -r -- "  \"audio_files\": ${MEDIA_AUDIO_COUNT},"
    print -r -- "  \"source_files\": ${source_files},"
    print -r -- "  \"copied_files\": ${copied_files},"
    print -r -- "  \"verified_files\": ${verified_files},"
    print -r -- "  \"source_bytes\": ${source_bytes},"
    print -r -- "  \"copied_bytes\": ${copied_bytes},"
    print -r -- "  \"duration_seconds\": ${elapsed},"
    print -r -- "  \"checksum_verify\": $(bool_is_true "$CHECKSUM_VERIFY" && print true || print false),"
    print -r -- "  \"verification\": \"$(json_escape "$verification")\""
    print -r -- "}"
  } > "$temp_manifest"
  command mv -f "$temp_manifest" "$manifest"
  log INFO "Shared import manifest written: $manifest"
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
  local device_identifier source_root volume_name destination capture_date manifest
  local volume_uuid volume_size
  local lock_dir shared_lock_dir rsync_output checksum_output verification_result
  local started_at elapsed imported_at speed_mib
  local batch_count batch_bytes
  local total_count total_bytes total_copied=0 total_copied_bytes=0 total_verified=0
  local overall_status=0
  local card_fingerprint final_verification
  local -a sorted_dates

  SCAN_COUNT=0
  SCAN_BYTES=0
  SCAN_FIRST=""
  CAPTURE_DATE=""
  CAPTURE_TIME=""
  CAMERA_MODEL=""
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
  volume_uuid="$(plist_value "$info_file" VolumeUUID)"
  volume_size="$(plist_value "$info_file" TotalSize)"
  command rm -f "$info_file"
  [[ -n "$device_identifier" ]] || device_identifier="${volume:t}"
  [[ -n "$volume_uuid" ]] || volume_uuid="no-volume-uuid"
  [[ -n "$volume_size" ]] || volume_size="unknown-size"

  if find_dcim_root "$volume"; then
    source_root="$REPLY"
  else
    source_root="$volume"
  fi

  if ! classify_images_by_date "$source_root"; then
    log INFO "Ignoring removable volume with no supported images: $volume"
    return 0
  fi

  if ! acquire_lock "$device_identifier"; then
    log INFO "Import already active; ignoring duplicate event for: $volume"
    remove_date_manifests
    return 0
  fi
  lock_dir="$REPLY"

  volume_name="${volume:t}"
  card_fingerprint="${volume_uuid}_${device_identifier}_${volume_name}_${volume_size}_${SCAN_COUNT}_${SCAN_BYTES}_${SCAN_FIRST}"
  if ! acquire_shared_lock "$card_fingerprint"; then
    log INFO "Shared import already active; ignoring duplicate card on another ingest station: $volume"
    write_shared_status "active" "Duplicate shared import ignored for ${volume_name}" \
      "$SCAN_COUNT" "$DESTINATION_ROOT" "$volume_name" || true
    remove_date_manifests
    release_lock "$lock_dir"
    return 0
  fi
  shared_lock_dir="${REPLY:-}"

  total_count="$SCAN_COUNT"
  total_bytes="$SCAN_BYTES"
  started_at=$SECONDS
  imported_at="$(iso_timestamp)"
  sorted_dates=("${(on)DATE_KEYS[@]}")

  log INFO "Import started: source=$volume files=$total_count bytes=$total_bytes capture_dates=${#sorted_dates[@]}"
  write_status "importing" "Sorting ${total_count} photos across ${#sorted_dates[@]} dates from ${volume_name}" \
    "$total_count" "$DESTINATION_ROOT" || true
  write_shared_status "importing" "Sorting ${total_count} photos across ${#sorted_dates[@]} dates from ${volume_name}" \
    "$total_count" "$DESTINATION_ROOT" "$volume_name" || true
  notify "Import started" "${total_count} photos across ${#sorted_dates[@]} dates from ${volume_name}"

  if ! preflight_destination_root; then
    write_status "error" "Destination unavailable: ${DESTINATION_ROOT}" \
      "$total_count" "$DESTINATION_ROOT" || true
    write_shared_status "error" "Destination unavailable: ${DESTINATION_ROOT}" \
      "$total_count" "$DESTINATION_ROOT" "$volume_name" || true
    notify "Import failed" "NAS destination is unavailable. ${volume_name} was left mounted."
    elapsed=$(( SECONDS - started_at ))
    (( elapsed < 1 )) && elapsed=1
    write_shared_import_manifest "failed" "$volume_name" "$DESTINATION_ROOT" "$imported_at" \
      "$elapsed" "$total_count" "$total_copied" "$total_verified" "$total_bytes" \
      "$total_copied_bytes" "failed (destination preflight)" || true
    remove_date_manifests
    release_shared_lock "$shared_lock_dir"
    release_lock "$lock_dir"
    return 1
  fi

  for capture_date in "${sorted_dates[@]}"; do
    CAPTURE_DATE="$capture_date"
    CAPTURE_TIME="${DATE_TIMES[$capture_date]}"
    CAMERA_MODEL="${DATE_CAMERAS[$capture_date]}"
    batch_count="${DATE_COUNTS[$capture_date]}"
    batch_bytes="${DATE_BYTES[$capture_date]}"
    manifest="${DATE_MANIFESTS[$capture_date]}"
    SCAN_COUNT="$batch_count"
    SCAN_BYTES="$batch_bytes"
    COPIED_COUNT=0
    COPIED_BYTES=0
    VERIFIED_COUNT=0
    RSYNC_EXIT_CODE=1
    verification_result="failed"

    if ! build_destination "$volume_name"; then
      log ERROR "Could not build destination for capture date: $capture_date"
      overall_status=1
      continue
    fi
    destination="$REPLY"
    rsync_output="${RUNTIME_ROOT}/rsync-${capture_date}.$$.$RANDOM.log"
    checksum_output="${RUNTIME_ROOT}/checksum-${capture_date}.$$.$RANDOM.log"

    if bool_is_true "$DRY_RUN"; then
      plan_dry_run_manifest "$source_root" "$destination" "$manifest"
      (( total_copied += COPIED_COUNT ))
      (( total_copied_bytes += COPIED_BYTES ))
      log INFO "Dry run batch: source=$volume capture_date=$capture_date destination=$destination would_copy=$COPIED_COUNT files=$batch_count"
      continue
    fi

    if ! command mkdir -p "$destination"; then
      log ERROR "Could not create destination: $destination"
      overall_status=1
      continue
    fi
    if ! create_workflow_scaffold "$destination"; then
      log ERROR "Could not create workflow scaffold: $destination"
      overall_status=1
      continue
    fi

    run_rsync_manifest "$source_root" "$destination" "$manifest" "$rsync_output"
    count_rsync_files "$rsync_output"
    command rm -f "$rsync_output"
    (( total_copied += COPIED_COUNT ))
    (( total_copied_bytes += COPIED_BYTES ))

    if (( RSYNC_EXIT_CODE == 0 )) &&
      verify_import_manifest "$source_root" "$destination" "$manifest" "$batch_count"; then
      (( total_verified += VERIFIED_COUNT ))
      if bool_is_true "$CHECKSUM_VERIFY"; then
        if verify_checksums_manifest "$source_root" "$destination" "$manifest" "$checksum_output"; then
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

    elapsed=$(( SECONDS - started_at ))
    (( elapsed < 1 )) && elapsed=1
    if [[ "$verification_result" == passed* ]]; then
      write_sidecar "$destination" "$volume_name" "$imported_at" "$elapsed"
      log INFO "Import batch complete: source=$volume capture_date=$capture_date destination=$destination copied=$COPIED_COUNT source_files=$batch_count verified_files=$VERIFIED_COUNT rsync_exit=$RSYNC_EXIT_CODE verification=$verification_result"
    else
      log ERROR "Import batch failed: source=$volume capture_date=$capture_date destination=$destination copied=$COPIED_COUNT source_files=$batch_count verified_files=$VERIFIED_COUNT rsync_exit=$RSYNC_EXIT_CODE verification=$verification_result"
      overall_status=1
    fi
  done

  elapsed=$(( SECONDS - started_at ))
  (( elapsed < 1 )) && elapsed=1
  speed_mib=$(( total_copied_bytes / elapsed / 1024 / 1024 ))
  remove_date_manifests
  SCAN_COUNT="$total_count"
  SCAN_BYTES="$total_bytes"

  if bool_is_true "$DRY_RUN"; then
    final_verification="not_run"
    log INFO "Dry run complete: source=$volume destination_root=$DESTINATION_ROOT capture_dates=${#sorted_dates[@]} would_copy=$total_copied elapsed_seconds=$elapsed estimated_mib_per_second=$speed_mib verification=not_run"
    write_status "active" "Dry run complete: ${total_copied} photos across ${#sorted_dates[@]} dates" \
      "$total_copied" "$DESTINATION_ROOT" || true
    write_shared_status "active" "Dry run complete: ${total_copied} photos across ${#sorted_dates[@]} dates" \
      "$total_copied" "$DESTINATION_ROOT" "$volume_name" || true
    write_shared_import_manifest "dry_run" "$volume_name" "$DESTINATION_ROOT" "$imported_at" \
      "$elapsed" "$total_count" "$total_copied" "$total_verified" "$total_bytes" \
      "$total_copied_bytes" "$final_verification" || true
    notify "Photo import dry run" "Would sort ${total_copied} photos into ${#sorted_dates[@]} date folders"
    release_shared_lock "$shared_lock_dir"
    release_lock "$lock_dir"
    return 0
  fi

  if (( overall_status == 0 && total_verified == total_count )); then
    final_verification="passed"
    log INFO "Import complete: source=$volume destination_root=$DESTINATION_ROOT capture_dates=${#sorted_dates[@]} copied=$total_copied source_files=$total_count verified_files=$total_verified elapsed_seconds=$elapsed speed_mib_per_second=$speed_mib verification=passed"
    write_status "active" "Import complete: ${total_count} photos across ${#sorted_dates[@]} dates" \
      "$total_count" "$DESTINATION_ROOT" || true
    write_shared_status "active" "Import complete: ${total_count} photos across ${#sorted_dates[@]} dates" \
      "$total_count" "$DESTINATION_ROOT" "$volume_name" || true
    write_shared_import_manifest "complete" "$volume_name" "$DESTINATION_ROOT" "$imported_at" \
      "$elapsed" "$total_count" "$total_copied" "$total_verified" "$total_bytes" \
      "$total_copied_bytes" "$final_verification" || true
    notify "Import complete" "${total_count} photos sorted into ${#sorted_dates[@]} date folders"
    bool_is_true "$AUTO_EJECT" && eject_volume "$volume"
    release_shared_lock "$shared_lock_dir"
    release_lock "$lock_dir"
    return 0
  fi

  final_verification="failed"
  log ERROR "Import failed: source=$volume destination_root=$DESTINATION_ROOT source_files=$total_count verified_files=$total_verified elapsed_seconds=$elapsed"
  write_status "error" "Import failed: ${total_verified} of ${total_count} verified" \
    "$total_count" "$DESTINATION_ROOT" || true
  write_shared_status "error" "Import failed: ${total_verified} of ${total_count} verified" \
    "$total_count" "$DESTINATION_ROOT" "$volume_name" || true
  write_shared_import_manifest "failed" "$volume_name" "$DESTINATION_ROOT" "$imported_at" \
    "$elapsed" "$total_count" "$total_copied" "$total_verified" "$total_bytes" \
    "$total_copied_bytes" "$final_verification" || true
  notify "Import failed" "Verified ${total_verified} of ${total_count} photos. ${volume_name} was left mounted."
  release_shared_lock "$shared_lock_dir"
  release_lock "$lock_dir"
  return 1
}

###############################################################################
# Main
###############################################################################

main() {
  local volume
  local overall_status=0

  MDLS_ENABLED=true

  command mkdir -p "${LOGFILE:h}"
  [[ -e "$LOGFILE" ]] || : > "$LOGFILE"
  command chmod 600 "$LOGFILE" 2>/dev/null || true
  prepare_runtime || return 1
  rotate_logs
  write_status "active" "Service active — waiting for a camera card" 0 "" || true
  load_configuration || {
    write_status "error" "Configuration is invalid" 0 "" || true
    notify "Cardy McCardface setup required" "Configuration is invalid. Run the setup wizard again."
    return 1
  }
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
