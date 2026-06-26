# Release checklist

Use this checklist before tagging a release.

## Local validation

```zsh
for script in CardyMcCardface/Resources/photo_import.sh CardyMcCardface/Resources/dashboard.sh install.sh uninstall.sh tests/smoke_test.zsh; do
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

## Manual validation

1. Run `./install.sh`.
2. Confirm `~/Applications/Cardy McCardface.app` launches.
3. Confirm the menu-bar item appears.
4. Open Settings and save a configuration.
5. Run a dry-run import from a test card.
6. Run a real import into a disposable destination.
7. Confirm:
   - imported files preserve relative card structure;
   - sidecar JSON is written;
   - ready handoff JSON is written;
   - dashboard opens;
   - log file updates;
   - failed verification leaves the card mounted.

## Privacy review

Before publishing release assets or screenshots, verify that they do not expose:

- personal paths;
- NAS paths;
- source volume names;
- card filenames;
- camera serials or client/project names;
- station/operator names;
- logs, manifests, or dashboard output from a real job.

## Tagging

After CI passes on `main`:

```zsh
git tag vX.Y.Z
git push origin vX.Y.Z
```
