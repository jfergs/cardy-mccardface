# Security policy

## Reporting a vulnerability

Please do not include card contents, filenames, volume names, NAS paths, logs,
or other personal information in a public issue.

Report suspected vulnerabilities privately through GitHub's security advisory
feature for this repository.

## Data handling

Cardy McCardface runs locally. It does not make network requests or mount
network shares. It writes:

- imported photo, video, and audio media to the configured destination;
- optionally preserved non-media card files to the configured destination;
- production scaffold directories under the configured destination;
- import metadata sidecars alongside imported images;
- optional shared ingest status under the configured destination;
- optional shared ingest manifests under the configured destination;
- optional shared ingest lock directories under the configured destination;
- app preferences under `~/Library/Application Support/CardyMcCardface`;
- menu bar state under `~/Library/Application Support/CardyMcCardface`;
- operational logs under `~/Library/Logs`;
- short-lived runtime files under the current user's macOS temporary directory.

Logs, sidecars, summary manifests, and JSONL file manifests can contain camera
models, source volume names, destination paths, workflow presets, media-type
counts, preserved-file counts, relative filenames, card structure, file counts,
and timestamps. Review them before sharing.

Notification previews can expose source volume names, destination paths, and
file counts on the lock screen. Disable notifications in the settings window or
adjust macOS notification preview settings when this information is sensitive.

Ingest Village mode is designed for shared production storage. Its shared
status and manifest files can expose station names, operator names, hostnames,
volume names, destination paths, counts, byte totals, timestamps, and
verification state to anyone with read access to the destination.

The menu bar dropdown also displays import status and can reveal the configured
destination. Treat access to the logged-in macOS session and shared destination
metadata as access to this operational metadata.
