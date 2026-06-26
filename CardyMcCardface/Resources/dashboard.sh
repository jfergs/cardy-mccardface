#!/bin/zsh
#
# Generate a static Cardy McCardface ingest dashboard.

set -eu
setopt NO_NOMATCH

DESTINATION_ROOT="${1:-}"
CONFIG_FILE="${CARDY_CONFIG_FILE:-${HOME}/Library/Application Support/CardyMcCardface/config.plist}"
STATUS_FILE="${CARDY_STATUS_FILE:-${HOME}/Library/Application Support/CardyMcCardface/status.plist}"
SUPPORT_DIR="${CARDY_SUPPORT_DIR:-${HOME}/Library/Application Support/CardyMcCardface}"
DASHBOARD_FILE="${SUPPORT_DIR}/dashboard.html"

plist_value() {
  local plist="$1"
  local key="$2"
  local output

  if output="$(/usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null)"; then
    print -r -- "$output"
  fi
}

html_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  print -r -- "$value"
}

json_string_value() {
  local file="$1"
  local key="$2"
  local line value

  while IFS= read -r line; do
    [[ "$line" == *"\"${key}\""* ]] || continue
    value="${line#*:}"
    value="${value##[[:space:]]#}"
    value="${value%,}"
    value="${value#\"}"
    value="${value%\"}"
    print -r -- "$value"
    return 0
  done < "$file"
  print -r -- ""
}

json_number_value() {
  local file="$1"
  local key="$2"
  local value

  value="$(json_string_value "$file" "$key")"
  value="${value//[^0-9]/}"
  [[ -n "$value" ]] || value=0
  print -r -- "$value"
}

if [[ -z "$DESTINATION_ROOT" && -f "$CONFIG_FILE" ]]; then
  DESTINATION_ROOT="$(plist_value "$CONFIG_FILE" destinationRoot)"
fi
[[ -n "$DESTINATION_ROOT" ]] || DESTINATION_ROOT="${HOME}/Pictures"

STATUS_DIR="${DESTINATION_ROOT}/.cardy-status"
IMPORT_DIR="${DESTINATION_ROOT}/.cardy-imports"
READY_DIR="${DESTINATION_ROOT}/.cardy-ready"

command mkdir -p "$SUPPORT_DIR"

{
  print -r -- "<!doctype html>"
  print -r -- "<html lang=\"en\"><head><meta charset=\"utf-8\">"
  print -r -- "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
  print -r -- "<title>Cardy McCardface Dashboard</title>"
  print -r -- "<style>"
  print -r -- "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:28px;background:#111;color:#eee}"
  print -r -- "h1,h2{margin-bottom:.35rem} table{border-collapse:collapse;width:100%;margin:1rem 0 2rem}"
  print -r -- "th,td{border-bottom:1px solid #333;padding:8px;text-align:left;font-size:14px;vertical-align:top}"
  print -r -- "th{color:#aaa} .ok{color:#7ee787}.bad{color:#ff7b72}.muted{color:#aaa}.card{background:#1b1b1b;border:1px solid #333;border-radius:12px;padding:16px;margin:12px 0}"
  print -r -- "</style></head><body>"
  print -r -- "<h1>Cardy McCardface Dashboard</h1>"
  print -r -- "<p class=\"muted\">Generated $(html_escape "$(command date '+%Y-%m-%d %H:%M:%S %Z')")</p>"
  print -r -- "<div class=\"card\"><strong>Destination:</strong> $(html_escape "$DESTINATION_ROOT")</div>"

  print -r -- "<h2>Stations</h2>"
  print -r -- "<table><thead><tr><th>Station</th><th>State</th><th>Message</th><th>Files</th><th>Updated</th><th>Destination</th></tr></thead><tbody>"
  if [[ -d "$STATUS_DIR" ]]; then
    for file in "$STATUS_DIR"/*.json(N); do
      station="$(json_string_value "$file" station_name)"
      state="$(json_string_value "$file" state)"
      message="$(json_string_value "$file" message)"
      count="$(json_number_value "$file" file_count)"
      updated="$(json_string_value "$file" updated_at)"
      destination="$(json_string_value "$file" destination)"
      css="muted"
      [[ "$state" == "active" ]] && css="ok"
      [[ "$state" == "error" ]] && css="bad"
      print -r -- "<tr><td>$(html_escape "$station")</td><td class=\"$css\">$(html_escape "$state")</td><td>$(html_escape "$message")</td><td>${count}</td><td>$(html_escape "$updated")</td><td>$(html_escape "$destination")</td></tr>"
    done
  fi
  print -r -- "</tbody></table>"

  print -r -- "<h2>Recent Imports</h2>"
  print -r -- "<table><thead><tr><th>Imported</th><th>State</th><th>Station</th><th>Source</th><th>Files</th><th>Photos</th><th>Video</th><th>Audio</th><th>Other</th><th>Verification</th></tr></thead><tbody>"
  if [[ -d "$IMPORT_DIR" ]]; then
    recent_imports=("$IMPORT_DIR"/*.json(Nom[1,25]))
    for file in "${recent_imports[@]}"; do
      imported="$(json_string_value "$file" imported_at)"
      state="$(json_string_value "$file" state)"
      station="$(json_string_value "$file" station_name)"
      source="$(json_string_value "$file" source_volume)"
      files="$(json_number_value "$file" source_files)"
      photos="$(json_number_value "$file" photo_files)"
      videos="$(json_number_value "$file" video_files)"
      audio="$(json_number_value "$file" audio_files)"
      other="$(json_number_value "$file" other_preserved_files)"
      verification="$(json_string_value "$file" verification)"
      css="muted"
      [[ "$state" == "complete" ]] && css="ok"
      [[ "$state" == "failed" ]] && css="bad"
      print -r -- "<tr><td>$(html_escape "$imported")</td><td class=\"$css\">$(html_escape "$state")</td><td>$(html_escape "$station")</td><td>$(html_escape "$source")</td><td>${files}</td><td>${photos}</td><td>${videos}</td><td>${audio}</td><td>${other}</td><td>$(html_escape "$verification")</td></tr>"
    done
  fi
  print -r -- "</tbody></table>"

  print -r -- "<h2>Ready Handoffs</h2>"
  print -r -- "<table><thead><tr><th>Ready</th><th>Station</th><th>Source</th><th>Files</th><th>Destination</th></tr></thead><tbody>"
  if [[ -d "$READY_DIR" ]]; then
    recent_ready=("$READY_DIR"/*.ready.json(Nom[1,25]))
    for file in "${recent_ready[@]}"; do
      ready="$(json_string_value "$file" ready_at)"
      station="$(json_string_value "$file" station_name)"
      source="$(json_string_value "$file" source_volume)"
      files="$(json_number_value "$file" source_files)"
      destination="$(json_string_value "$file" destination_root)"
      print -r -- "<tr><td>$(html_escape "$ready")</td><td>$(html_escape "$station")</td><td>$(html_escape "$source")</td><td>${files}</td><td>$(html_escape "$destination")</td></tr>"
    done
  fi
  print -r -- "</tbody></table>"

  print -r -- "</body></html>"
} > "$DASHBOARD_FILE"

print -r -- "$DASHBOARD_FILE"
