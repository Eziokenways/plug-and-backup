Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$IsChineseUi = [System.Globalization.CultureInfo]::CurrentUICulture.Name.StartsWith("zh", [System.StringComparison]::OrdinalIgnoreCase)
$AppName = if ($IsChineseUi) { "随插备份" } else { "Plug & Backup" }
$ShortcutDescription = if ($IsChineseUi) { "在系统托盘中启动随插备份。" } else { "Start Plug & Backup in the system tray." }
$CreatedMessage = if ($IsChineseUi) { "已创建开机启动快捷方式：" } else { "Startup shortcut created:" }
$ScriptPath = Join-Path $PSScriptRoot "UsbPhotoBackup.ps1"
$IconPath = Join-Path (Join-Path $PSScriptRoot "assets") "usb-backup.ico"

if (-not [System.IO.File]::Exists($ScriptPath)) {
    throw "UsbPhotoBackup.ps1 was not found next to this installer."
}

$StartupDir = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $StartupDir "$AppName.lnk"
$PowerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $PowerShellPath
$shortcut.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -StartMinimized"
$shortcut.WorkingDirectory = $PSScriptRoot
if ([System.IO.File]::Exists($IconPath)) {
    $shortcut.IconLocation = $IconPath
}
else {
    $shortcut.IconLocation = "$PowerShellPath,0"
}
$shortcut.Description = $ShortcutDescription
$shortcut.Save()

Write-Host $CreatedMessage
Write-Host $ShortcutPath
