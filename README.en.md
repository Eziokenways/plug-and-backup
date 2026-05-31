# Plug & Backup / 随插备份

<p align="center">
  <img src="assets/usb-backup.png" alt="Plug & Backup / 随插备份" width="160">
</p>

[中文 README](./README.md)

A portable Windows tray app for automatically backing up photos, videos, and camera RAW files from USB drives, card readers, camera memory cards, and external hard drives.

Its goal is simple: insert a device, confirm trust, and safely copy media files to your backup folder. The app copies files only, does not delete original files, and does not write hidden marker files to memory cards or USB devices by default.

## Download

Download `PlugAndBackup.exe` from GitHub Releases.

- Portable app, no installer required.
- No extra runtime software required.
- Version 1.0 is not code-signed. Windows SmartScreen may show a warning on first launch, which is common for unsigned software.

## Highlights

- Stays in the system tray and monitors connected devices in the background.
- Supports Chinese / English UI based on the Windows display language.
- Supports photos, videos, and common camera RAW formats.
- Automatically or manually scans USB drives, card readers, camera cards, and external hard drives.
- Uses local composite fingerprints to recognize trusted sources without relying on writing to memory cards.
- Supports Trust and back up, Skip this time, and Always skip.
- Supports automatic backup or confirm-before-backup-after-insert mode.
- Uses SHA-256 content deduplication.
- Automatically renames same-name files with different contents instead of overwriting existing files.
- Can archive by date, device, Photos / Videos / RAW, and original source folder structure.
- Supports startup with Windows, silent notifications, minimum file size, excluded folders, and custom extensions.
- Provides backup history, open recent backup location, log folder access, diagnostics export, and cleanup/uninstall data flow.

## Default Supported Formats

- Photos: `jpg/jpeg/png/heic/webp/gif/bmp/tif/tiff`
- Videos: `mp4/mov/avi/mkv/m4v/3gp/wmv/mts/m2ts`
- RAW: `dng/cr2/cr3/nef/arw/raf/orf/rw2/pef/sr2/x3f/crw/iiq/3fr`

Supported formats can be customized in the settings window.

## Quick Start

1. Download and run `PlugAndBackup.exe`.
2. Choose a backup folder on first launch.
3. Adjust backup mode and archive options in the settings window if needed.
4. Insert a USB device, card reader, or external hard drive.
5. Choose trust, skip, or always skip in the prompt.

After launch, the app appears in the system tray. Right-click the tray icon to scan now, pause automatic backup, open the backup folder, open the recent backup location, open settings, or exit.

## Backup Folder Structure

Default structure:

```text
<Backup folder>\YYYY\YYYY-MM-DD\File name
```

Optional combined structure:

```text
<Backup folder>\<Device name>\Photos\YYYY\YYYY-MM-DD\File name
<Backup folder>\<Device name>\Videos\YYYY\YYYY-MM-DD\File name
<Backup folder>\<Device name>\RAW\YYYY\YYYY-MM-DD\File name
```

If different devices use the same name, the app automatically appends a short fingerprint suffix, such as `CAMERA-8F3A2C`.

## Safety Boundaries

- Does not delete files from USB drives, memory cards, or backup folders.
- Does not write hidden marker files to USB drives or memory cards by default.
- Does not scan the Windows system drive.
- To avoid scanning local data by mistake, it only handles removable drives or external Fixed drives that can be identified as USB/SD/MMC attached.
- MTP phones are not scanned unless Windows exposes them as a drive letter.
- This version archives by file modified time and does not yet read EXIF or video capture-time metadata.

## Config and Logs

- Config: `%APPDATA%\UsbPhotoBackup\config.json`
- Deduplication index: `%LOCALAPPDATA%\UsbPhotoBackup\manifest.json`
- Recent backup result: `%LOCALAPPDATA%\UsbPhotoBackup\last-backup.json`
- Log: `%LOCALAPPDATA%\UsbPhotoBackup\logs\backup.log`

The settings window includes a cleanup/uninstall data action. It only removes local config, logs, deduplication index, and startup shortcut. It does not delete backed-up files.

## Run from Source

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\UsbPhotoBackup.ps1
```

## Build

The build machine needs PS2EXE:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-PortableExe.ps1
```

Output files are generated under `dist\`. See [BUILD.md](./BUILD.md).

## License

MIT License. See [LICENSE](./LICENSE).
