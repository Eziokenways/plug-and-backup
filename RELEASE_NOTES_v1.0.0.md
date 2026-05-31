# Plug & Backup v1.0.0

First public release of Plug & Backup / 随插备份.

## Highlights

- Windows portable tray app for backing up photos, videos, and camera RAW files from USB drives, card readers, and external drives.
- Keeps original files on the source device.
- Does not write marker files to memory cards or USB drives by default.
- Uses local trusted/skipped source fingerprints.
- Supports automatic backup or confirm-before-backup mode.
- Supports permanent skipped sources for devices that should never prompt again.
- Archives by date, with optional Photos / Videos / RAW folders, per-device folders, and original source folder structure.
- Uses SHA-256 deduplication and avoids overwriting same-name different-content files.

## Download

Download `PlugAndBackup.exe` from this release. The app does not require an installer.

## Notes

- Unsigned exe builds may show a Windows SmartScreen warning on first launch.
- Runtime has no extra dependency beyond Windows PowerShell 5.1 and built-in Windows Forms.
- See `README.md` for setup, settings, cleanup, and troubleshooting details.

## Release Assets

- `PlugAndBackup.exe`
- `README.md`
- `CHANGELOG.md`
- `SHA256SUMS.txt`
