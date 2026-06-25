# Cardy McCardface

Cardy McCardface automatically imports photos from removable camera cards on
macOS. A per-user LaunchAgent watches for mounted volumes, identifies camera
media, copies supported images with `rsync`, verifies the result, writes a JSON
import sidecar, and optionally ejects the card.

It uses software included with macOS. If `exiftool` is already installed, it is
used for richer capture metadata; otherwise the importer falls back to `mdls`
and file creation dates.

## Requirements

- macOS with `zsh`, `launchd`, `rsync`, `diskutil`, `mdls`, and `osascript`
- A destination volume that is already mounted
- Read access to removable media and write access to the destination

Cardy McCardface does not mount SMB or other network shares.

## Configure before installation

Edit the configuration block at the top of `photo_import.sh`:

```zsh
DESTINATION_ROOT="/Volumes/PhotoNAS/Photos"
AUTO_EJECT=true
SUPPORTED_EXTENSIONS=(CR3 CR2 NEF ARW RAF ORF RW2 DNG JPG JPEG HEIC PNG TIF TIFF)
LOGFILE="${HOME}/Library/Logs/CardyMcCardface.log"
DRY_RUN=false
```

Also review:

```zsh
CHECKSUM_VERIFY=false
EXCLUDED_VOLUMES=("/Volumes/PhotoNAS" "/Volumes/Macintosh HD")
MIN_CARD_SIZE_GB=0
```

Use the actual mount point of your already-mounted destination. Add its volume
root to `EXCLUDED_VOLUMES` so it can never be considered an import source.

For a first test, set `DRY_RUN=true` and `AUTO_EJECT=false`.

## Install

```zsh
chmod 755 install.sh uninstall.sh photo_import.sh
./install.sh
```

The installer copies files to:

- `~/Library/Scripts/CardyMcCardface/photo_import.sh`
- `~/Library/LaunchAgents/com.cardymccardface.photoimporter.plist`

Configuration changes made after installation must be applied to the installed
script, or followed by another `./install.sh`.

## How mounting triggers an import

The LaunchAgent combines three launchd mechanisms:

- `StartOnMount` starts the job when a filesystem is mounted.
- `WatchPaths` observes changes under `/Volumes`.
- `RunAtLoad` scans cards that were already mounted when the agent loaded.

Launchd does not pass the new volume path to the job. The script therefore
rescans `/Volumes`, accepts only removable media, ignores configured volumes,
and uses a per-device lock to prevent overlapping imports.

## Import layout

The capture date is selected from the first supported image using:

1. EXIF `DateTimeOriginal`
2. EXIF `CreateDate`
3. Spotlight content creation date
4. File creation date

Files are imported into:

```text
DESTINATION_ROOT/YYYY/YYYY-MM-DD/
```

Directory structure beneath `DCIM` is preserved. Existing destination files
are skipped and are never overwritten.

Each successful import also writes a `photo-import-*.json` sidecar containing
the import timestamp, camera model, capture date, source volume name, counts,
bytes, duration, and verification status.

## Logs and troubleshooting

Follow the log:

```zsh
tail -f ~/Library/Logs/CardyMcCardface.log
```

Inspect launchd state:

```zsh
launchctl print "gui/$(id -u)/com.cardymccardface.photoimporter"
```

Force a rescan:

```zsh
launchctl kickstart -k "gui/$(id -u)/com.cardymccardface.photoimporter"
```

If access is denied, review macOS Privacy & Security permissions for removable
volumes, network volumes, and the shell process running the agent.

If verification fails, the card remains mounted. Partial transfers are retained
in `.photoimport-partial` and can resume on a later run.

## Uninstall

```zsh
./uninstall.sh
```

Logs are intentionally retained. Remove them separately if desired:

```zsh
rm -f ~/Library/Logs/CardyMcCardface.log*
```

## Privacy

The importer is local-only and has no telemetry. Logs and JSON sidecars may
contain camera models, volume names, local destination paths, counts, and
timestamps. Do not publish them without review.

## Development

Run local validation on macOS:

```zsh
/bin/zsh -n photo_import.sh install.sh uninstall.sh tests/smoke_test.zsh
/usr/bin/plutil -lint com.cardymccardface.photoimporter.plist
/bin/zsh tests/smoke_test.zsh
```

The GitHub Actions workflow runs the same checks on a macOS runner with
read-only repository permissions.

## License

MIT
