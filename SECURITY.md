# Security policy

## Reporting a vulnerability

Please do not include card contents, filenames, volume names, NAS paths, logs,
or other personal information in a public issue.

Report suspected vulnerabilities privately through GitHub's security advisory
feature for this repository.

## Data handling

Cardy McCardface runs locally. It does not make network requests or mount
network shares. It writes:

- imported images to the configured destination;
- import metadata sidecars alongside imported images;
- app preferences under `~/Library/Application Support/CardyMcCardface`;
- menu bar state under `~/Library/Application Support/CardyMcCardface`;
- operational logs under `~/Library/Logs`;
- short-lived runtime files under the current user's macOS temporary directory.

Logs and sidecars can contain camera models, source volume names, destination
paths, file counts, and timestamps. Review them before sharing.

Notification previews can expose source volume names, destination paths, and
file counts on the lock screen. Disable notifications in the settings window or
adjust macOS notification preview settings when this information is sensitive.

The menu bar dropdown also displays import status and can reveal the configured
destination. Treat access to the logged-in macOS session as access to this
operational metadata.
