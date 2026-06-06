# Changelog

## 1.0.1

- Changed backup-folder validation so an offline NAS or network backup path no longer forces folder selection at app startup after a folder has already been configured.
- Added a delayed prompt that appears only when a device is ready to back up and the configured backup folder is offline or not writable.
- Added choices to skip backup for the current device insertion or choose another backup folder and continue.
- Updated the portable exe release filename to include the version number.

## 1.0.0

- Released the first portable exe build of Plug & Backup / 随插备份.
- Added tray app workflow with localized Chinese/English UI, settings window, app icon, startup shortcut support, and cleanup/uninstall data flow.
- Added trusted source and skipped source management, including Trust and back up, Skip this time, and Always skip choices.
- Added no-write memory card identification using local composite fingerprints, with legacy marker read-only compatibility.
- Added automatic backup and confirm-before-backup modes, plus pause/resume automatic backup from the tray menu.
- Added photo, video, and camera RAW backup with configurable file extensions, SHA-256 deduplication, and same-name conflict handling.
- Added archive options for Photos / Videos / RAW folders, per-device folders, same-name device short-hash disambiguation, preserving source structure, minimum file size, and excluded folders.
- Added recent backup result, open recent backup folder, open log folder, diagnostics export, and about dialog.
- Added safer fixed-disk handling: internal SATA/NVMe-style fixed disks are excluded, logged once, then silently skipped during repeated scans.
- Added BUILD.md and Build-PortableExe.ps1 for PS2EXE packaging.

## Notes

- Runtime has no extra dependency beyond Windows PowerShell 5.1 and built-in Windows Forms.
- The app copies files only. It does not delete files from USB drives, memory cards, or backup folders.
- By default, the app does not write marker files to memory cards or USB drives.
- Unsigned exe builds may show Windows SmartScreen warnings on first launch.
