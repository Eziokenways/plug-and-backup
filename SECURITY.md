# Security Policy

## Reporting

Please report security issues through GitHub issues or a private contact channel if one is listed on the repository.

Do not attach private photos, videos, memory card contents, full backup folders, or logs that may contain personal file paths. When reporting a problem, prefer:

- App version
- Windows version
- Device type, such as USB drive, card reader, or external hard drive
- Relevant error text
- A redacted excerpt from `%LOCALAPPDATA%\UsbPhotoBackup\logs\backup.log`

## Data Handling

Plug & Backup stores configuration and logs locally under:

```text
%APPDATA%\UsbPhotoBackup
%LOCALAPPDATA%\UsbPhotoBackup
```

The app copies files only. It does not delete files from USB drives or memory cards, and current versions do not write marker files to those devices by default.
