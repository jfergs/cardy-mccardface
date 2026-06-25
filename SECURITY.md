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
- operational logs under `~/Library/Logs`;
- short-lived runtime files under the current user's macOS temporary directory.

Logs and sidecars can contain camera models, source volume names, destination
paths, file counts, and timestamps. Review them before sharing.
