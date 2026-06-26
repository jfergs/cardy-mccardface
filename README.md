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

## Privacy

Cardy is local-only. Logs, sidecars, notifications, and the menu can contain
camera models, volume names, destination paths, counts, and timestamps.

## License

MIT
