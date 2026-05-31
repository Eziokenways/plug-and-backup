# Plug & Backup / 随插备份 v1.0.0

This is the first public release of Plug & Backup / 随插备份.

Plug & Backup is a portable Windows tray app for automatically backing up photos, videos, and camera RAW files from USB drives, card readers, camera memory cards, and external hard drives. It does not require an installer: download `PlugAndBackup.exe` and run it directly.

## Highlights

- Automatically detects USB devices, card readers, camera memory cards, and external hard drives.
- Supports photos, videos, and common camera RAW formats.
- Copies files only, and does not delete original files from USB drives or memory cards.
- Does not write hidden marker files to memory cards or USB devices by default.
- Uses locally stored composite fingerprints to recognize trusted sources.
- Supports both automatic backup and confirm-before-backup-after-insert modes.
- Supports always-skipped sources for devices that should not prompt repeatedly.
- Archives by date, with optional Photos / Videos / RAW folders, per-device folders, and original source folder structure.
- Automatically adds a short fingerprint suffix when different devices have the same display name.
- Uses SHA-256 content deduplication to avoid repeated backups.
- Avoids overwriting same-name files with different contents by automatically renaming the new copy.
- Provides a settings window, backup history, log folder access, diagnostics export, and cleanup/uninstall data flow.

## Downloads

Download the following files from this release:

- `PlugAndBackup.exe`: main app
- `README.md`: user guide
- `CHANGELOG.md`: changelog
- `SHA256SUMS.txt`: file checksums

## Usage

On first launch, the app asks you to choose a backup folder and then opens the settings window. After that, it stays in the system tray.

Right-click the tray icon to scan now, pause automatic backup, open the backup folder, open the recent backup location, open settings, or exit the app.

## Notes

- This is a portable app and does not require a traditional installer.
- Runtime has no extra software dependency.
- Version 1.0 is not code-signed. Windows SmartScreen may show a warning on first launch, which is common for unsigned software.
- The app does not delete files from USB drives, memory cards, or backup folders.
- This version archives by file modified time and does not yet read EXIF or video capture-time metadata.
- MTP phones are not scanned unless Windows exposes them as a drive letter.

## SHA-256

`PlugAndBackup.exe`:

```text
cb7910775e79c14f1655da059f63ad0a82d4f32e442e5575e26b82cb3b485c7f
```
