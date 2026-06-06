Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$AppVersion = "1.0.1"
$ExeVersion = "1.0.1.0"
$ProductName = "Plug & Backup"
$ScriptPath = Join-Path $PSScriptRoot "UsbPhotoBackup.ps1"
$IconPath = Join-Path (Join-Path $PSScriptRoot "assets") "usb-backup.ico"
$DistDir = Join-Path $PSScriptRoot "dist"
$OutputFileName = "PlugAndBackup-v$AppVersion.exe"
$OutputPath = Join-Path $DistDir $OutputFileName
$ChecksumPath = Join-Path $DistDir "SHA256SUMS.txt"

if (-not [System.IO.File]::Exists($ScriptPath)) {
    throw "UsbPhotoBackup.ps1 was not found next to this build script."
}

if (-not [System.IO.File]::Exists($IconPath)) {
    throw "Icon file was not found: $IconPath"
}

$ps2exe = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
if ($null -eq $ps2exe) {
    throw "PS2EXE is not installed. Install it on the build machine only, then run this script again. Example: Install-Module ps2exe -Scope CurrentUser"
}

if (-not [System.IO.Directory]::Exists($DistDir)) {
    [System.IO.Directory]::CreateDirectory($DistDir) | Out-Null
}

Get-ChildItem -LiteralPath $DistDir -File |
    Where-Object { $_.Name -like "PlugAndBackup*.exe" -or $_.Name -in @("README.md", "CHANGELOG.md", "SHA256SUMS.txt") -or $_.Name -like "RELEASE_NOTES_v*.md" } |
    Remove-Item -Force

Invoke-ps2exe `
    -inputFile $ScriptPath `
    -outputFile $OutputPath `
    -iconFile $IconPath `
    -noConsole `
    -STA `
    -title $ProductName `
    -description "USB and camera card photo/video backup tray tool." `
    -product $ProductName `
    -version $ExeVersion `
    -copyright "Copyright (c) 2026"

Copy-Item -LiteralPath (Join-Path $PSScriptRoot "README.md") -Destination (Join-Path $DistDir "README.md") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "CHANGELOG.md") -Destination (Join-Path $DistDir "CHANGELOG.md") -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "RELEASE_NOTES_v$AppVersion.md") -Destination (Join-Path $DistDir "RELEASE_NOTES_v$AppVersion.md") -Force

$releaseFiles = @(
    $OutputFileName,
    "README.md",
    "CHANGELOG.md",
    "RELEASE_NOTES_v$AppVersion.md"
)
$checksumLines = foreach ($fileName in $releaseFiles) {
    $filePath = Join-Path $DistDir $fileName
    $hash = Get-FileHash -LiteralPath $filePath -Algorithm SHA256
    "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $fileName
}
Set-Content -LiteralPath $ChecksumPath -Value $checksumLines -Encoding UTF8

Write-Host "Build complete:"
Write-Host $OutputPath
Write-Host $ChecksumPath
