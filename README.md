# Cardy McCardface

Cardy McCardface is a native macOS menu-bar application that automatically
imports photos from removable camera cards.

The app watches for newly mounted volumes, runs the bundled `zsh`/`rsync`
importer, verifies copied files, reports progress through Notification Center,
and optionally ejects the card.

## Features

- Native macOS menu-bar application
- Automatic detection of mounted camera cards
- Destination-folder picker and settings window
- One folder per day or multiple shoots per day
- Configurable date layouts:
  - `YYYY/YYYY-MM-DD`
  - `YYYY-MM-DD`
  - `YYYY/MM/DD`
- Shoot folders named by time, card name, or camera model
- Resumable `rsync` imports that skip existing files
- Count/size verification with optional checksums
- Native macOS notifications
- Import-status menu-bar icon
- Optional automatic eject
- Dry-run mode
- JSON import sidecars
- Ingest Village mode for multiple ingest stations writing to one shared volume
- Local-only operation with no telemetry

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools when installing from source
- A destination folder that is already mounted and writable

Cardy does not mount SMB or other network shares.

Install the command-line tools if needed:

```zsh
xcode-select --install
```

## Install from source

```zsh
git clone https://github.com/jfergs/cardy-mccardface.git
cd cardy-mccardface
chmod 755 install.sh uninstall.sh CardyMcCardface/Resources/photo_import.sh
./install.sh
```

The installer builds and signs the app locally, then installs it at:

```text
~/Applications/Cardy McCardface.app
```

On first launch, Cardy opens its settings window and does not import until a
configuration is saved. Choose the destination and review the import options.
Existing settings from earlier versions are reused.

## Menu bar

The menu displays:

- current service/import status;
- Settings;
- Scan Mounted Volumes;
- Open Import Log;
- Reveal Destination;
- Launch at Login;
- Quit.

The icon changes while importing or when an error needs attention.

Cardy registers itself as a macOS login item through `SMAppService`. Login items
can also be reviewed under **System Settings → General → Login Items**.

## Card detection

Cardy subscribes to macOS workspace mount notifications and runs an initial scan
when the app launches. A removable volume is considered a camera card if it has
a `DCIM` directory or contains a supported image.

Supported extensions:

```text
CR3 CR2 NEF ARW RAF ORF RW2 DNG JPG JPEG HEIC PNG TIF TIFF
```

Hidden files and hidden directories are ignored.

## Capture date and destination

The first supported image determines the shoot date:

1. EXIF `DateTimeOriginal`
2. EXIF `CreateDate`
3. Spotlight content creation date
4. File creation date

The default layout is:

```text
DESTINATION_ROOT/YYYY/YYYY-MM-DD/
```

Separate-shoot mode adds a timestamped shoot directory beneath the date.

## Ingest Village mode

Ingest Village mode is intended for productions where several Macs ingest cards
to the same NAS, SAN, or other already-mounted network destination while editors
work from that shared storage.

When enabled, Cardy uses safer production defaults:

- separate shoot folders are used to avoid filename and folder collisions;
- checksum verification is enabled;
- automatic eject is disabled;
- shared destination locks are enabled;
- shared station status JSON is written;
- shared import manifest JSON is written.

By default, shared coordination files are written beneath the destination root:

```text
DESTINATION_ROOT/
  .cardy-status/
    Ingest-01.json
  .cardy-imports/
    2026-06-25T14-33-18-04-00_Ingest-01_EOS_DIGITAL.json
  .cardy-locks/
    card-fingerprint.lock/
```

The settings window includes:

- station name;
- optional operator name;
- minimum card size;
- minimum destination free space;
- shared status/manifests/locks toggles.

Cardy uses atomic directory creation for shared locks. This is conservative and
works better on network filesystems than lock files that must be updated in
place. Locks older than 24 hours are treated as stale.

Before copying, Cardy preflights the destination by verifying that the root
exists, is writable, and meets the configured free-space threshold.

## Configuration and state

Settings are stored as a data-only property list:

```text
~/Library/Application Support/CardyMcCardface/config.plist
```

Current importer state is stored at:

```text
~/Library/Application Support/CardyMcCardface/status.plist
```

## Logging

Follow the importer log:

```zsh
tail -f ~/Library/Logs/CardyMcCardface.log
```

If verification fails, the card remains mounted. Interrupted transfers retain
partial files and can resume later.

## Uninstall

```zsh
./uninstall.sh
```

The uninstaller removes the app and login registration. Settings, logs, and
imported photos are retained.

## Development

Run local validation:

```zsh
for script in CardyMcCardface/Resources/photo_import.sh install.sh uninstall.sh tests/smoke_test.zsh; do
  /bin/zsh -n "$script"
done

/usr/bin/plutil -lint CardyMcCardface/Info.plist

/usr/bin/xcodebuild \
  -project CardyMcCardface.xcodeproj \
  -scheme CardyMcCardface \
  -configuration Release \
  -derivedDataPath /tmp/CardyMcCardfaceDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

/bin/zsh tests/smoke_test.zsh
```

## Roadmap

The ingest-village work is being built in staged sprints:

1. Multi-station foundation: station identity, shared status, shared manifests,
   shared locks, destination preflight.
2. Production folder presets: Capture One session, Adobe/Bridge/Lightroom,
   Premiere/Resolve, and hybrid photo/video layouts.
3. Media expansion: video/audio extensions, full-card video preservation, and
   per-media manifests.
4. Post-import handoff: reveal/open destination, launch Capture One or Adobe
   apps, and optional watched-folder integration.
5. Shared dashboard: read `.cardy-status` and `.cardy-imports` files to show a
   live ingest board for assistants and remote editors.

## Privacy

Cardy is local-only. Logs, sidecars, notifications, and the menu can contain
camera models, volume names, destination paths, counts, and timestamps.

## License

MIT
