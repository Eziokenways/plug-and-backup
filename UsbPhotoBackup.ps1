param(
    [switch]$StartMinimized,
    [switch]$Uninstall
)

Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class UsbPhotoBackupNative
{
    private const uint GENERIC_READ = 0x80000000;
    private const uint FILE_SHARE_READ = 0x00000001;
    private const uint FILE_SHARE_WRITE = 0x00000002;
    private const uint OPEN_EXISTING = 3;
    private const uint IOCTL_STORAGE_QUERY_PROPERTY = 0x002D1400;
    private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

    [StructLayout(LayoutKind.Sequential)]
    private struct STORAGE_PROPERTY_QUERY
    {
        public int PropertyId;
        public int QueryType;
        public byte AdditionalParameters;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct STORAGE_DEVICE_DESCRIPTOR
    {
        public uint Version;
        public uint Size;
        public byte DeviceType;
        public byte DeviceTypeModifier;
        [MarshalAs(UnmanagedType.U1)]
        public bool RemovableMedia;
        [MarshalAs(UnmanagedType.U1)]
        public bool CommandQueueing;
        public uint VendorIdOffset;
        public uint ProductIdOffset;
        public uint ProductRevisionOffset;
        public uint SerialNumberOffset;
        public int BusType;
        public uint RawPropertiesLength;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CreateFile(string lpFileName, uint dwDesiredAccess, uint dwShareMode, IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool DeviceIoControl(IntPtr hDevice, uint dwIoControlCode, IntPtr lpInBuffer, int nInBufferSize, byte[] lpOutBuffer, int nOutBufferSize, out int lpBytesReturned, IntPtr lpOverlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GetVolumeNameForVolumeMountPoint(string lpszVolumeMountPoint, StringBuilder lpszVolumeName, int cchBufferLength);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GetVolumeInformation(
        string lpRootPathName,
        StringBuilder lpVolumeNameBuffer,
        int nVolumeNameSize,
        out uint lpVolumeSerialNumber,
        out uint lpMaximumComponentLength,
        out uint lpFileSystemFlags,
        StringBuilder lpFileSystemNameBuffer,
        int nFileSystemNameSize);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern uint QueryDosDevice(string lpDeviceName, StringBuilder lpTargetPath, int ucchMax);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NOTIFYICONDATA
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;
        public uint uTimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Shell_NotifyIcon(uint dwMessage, ref NOTIFYICONDATA lpData);

    public static bool ShowSilentBalloon(IntPtr handle, int id, string title, string text, int iconFlags, int timeoutMs)
    {
        if (handle == IntPtr.Zero || id < 0)
        {
            return false;
        }

        NOTIFYICONDATA data = new NOTIFYICONDATA();
        data.cbSize = (uint)Marshal.SizeOf(typeof(NOTIFYICONDATA));
        data.hWnd = handle;
        data.uID = (uint)id;
        data.uFlags = 0x00000010;
        data.szInfoTitle = String.IsNullOrEmpty(title) ? "" : title;
        data.szInfo = String.IsNullOrEmpty(text) ? "" : text;
        data.uTimeoutOrVersion = (uint)Math.Max(1000, timeoutMs);
        data.dwInfoFlags = (uint)(iconFlags | 0x00000010);
        return Shell_NotifyIcon(0x00000001, ref data);
    }

    private static string ReadDescriptorString(byte[] output, IntPtr baseAddress, uint offset)
    {
        if (offset == 0 || offset >= output.Length)
        {
            return null;
        }

        string value = Marshal.PtrToStringAnsi(IntPtr.Add(baseAddress, (int)offset));
        if (String.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return value.Trim().Replace("\r", " ").Replace("\n", " ").Replace("\t", " ");
    }

    private static string DescriptorPair(string name, string value)
    {
        return name + "=" + (String.IsNullOrWhiteSpace(value) ? "" : value);
    }

    public static string GetStorageDeviceDescriptor(string rootPath)
    {
        if (String.IsNullOrWhiteSpace(rootPath))
        {
            return null;
        }

        string drive = rootPath.TrimEnd('\\');
        string devicePath = @"\\.\" + drive;
        IntPtr handle = CreateFile(devicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle == INVALID_HANDLE_VALUE)
        {
            handle = CreateFile(devicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        }
        if (handle == INVALID_HANDLE_VALUE)
        {
            return null;
        }

        IntPtr queryPtr = IntPtr.Zero;
        try
        {
            STORAGE_PROPERTY_QUERY query = new STORAGE_PROPERTY_QUERY();
            query.PropertyId = 0;
            query.QueryType = 0;
            int querySize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
            queryPtr = Marshal.AllocHGlobal(querySize);
            Marshal.StructureToPtr(query, queryPtr, false);

            byte[] output = new byte[4096];
            int bytesReturned;
            if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, queryPtr, querySize, output, output.Length, out bytesReturned, IntPtr.Zero))
            {
                return null;
            }

            GCHandle pinned = GCHandle.Alloc(output, GCHandleType.Pinned);
            try
            {
                IntPtr baseAddress = pinned.AddrOfPinnedObject();
                STORAGE_DEVICE_DESCRIPTOR descriptor = (STORAGE_DEVICE_DESCRIPTOR)Marshal.PtrToStructure(baseAddress, typeof(STORAGE_DEVICE_DESCRIPTOR));
                StringBuilder builder = new StringBuilder();
                builder.AppendLine(DescriptorPair("VendorId", ReadDescriptorString(output, baseAddress, descriptor.VendorIdOffset)));
                builder.AppendLine(DescriptorPair("ProductId", ReadDescriptorString(output, baseAddress, descriptor.ProductIdOffset)));
                builder.AppendLine(DescriptorPair("ProductRevision", ReadDescriptorString(output, baseAddress, descriptor.ProductRevisionOffset)));
                builder.AppendLine(DescriptorPair("SerialNumber", ReadDescriptorString(output, baseAddress, descriptor.SerialNumberOffset)));
                builder.AppendLine(DescriptorPair("BusType", descriptor.BusType.ToString()));
                builder.AppendLine(DescriptorPair("RemovableMedia", descriptor.RemovableMedia ? "True" : "False"));
                return builder.ToString();
            }
            finally
            {
                pinned.Free();
            }
        }
        finally
        {
            if (queryPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(queryPtr);
            }
            CloseHandle(handle);
        }
    }

    public static string GetStorageDeviceSerial(string rootPath)
    {
        if (String.IsNullOrWhiteSpace(rootPath))
        {
            return null;
        }

        string drive = rootPath.TrimEnd('\\');
        string devicePath = @"\\.\" + drive;
        IntPtr handle = CreateFile(devicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle == INVALID_HANDLE_VALUE)
        {
            handle = CreateFile(devicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        }
        if (handle == INVALID_HANDLE_VALUE)
        {
            return null;
        }

        IntPtr queryPtr = IntPtr.Zero;
        try
        {
            STORAGE_PROPERTY_QUERY query = new STORAGE_PROPERTY_QUERY();
            query.PropertyId = 0;
            query.QueryType = 0;
            int querySize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
            queryPtr = Marshal.AllocHGlobal(querySize);
            Marshal.StructureToPtr(query, queryPtr, false);

            byte[] output = new byte[4096];
            int bytesReturned;
            if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, queryPtr, querySize, output, output.Length, out bytesReturned, IntPtr.Zero))
            {
                return null;
            }

            GCHandle pinned = GCHandle.Alloc(output, GCHandleType.Pinned);
            try
            {
                STORAGE_DEVICE_DESCRIPTOR descriptor = (STORAGE_DEVICE_DESCRIPTOR)Marshal.PtrToStructure(pinned.AddrOfPinnedObject(), typeof(STORAGE_DEVICE_DESCRIPTOR));
                if (descriptor.SerialNumberOffset == 0 || descriptor.SerialNumberOffset >= output.Length)
                {
                    return null;
                }

                string serial = Marshal.PtrToStringAnsi(IntPtr.Add(pinned.AddrOfPinnedObject(), (int)descriptor.SerialNumberOffset));
                if (String.IsNullOrWhiteSpace(serial))
                {
                    return null;
                }
                return serial.Trim();
            }
            finally
            {
                pinned.Free();
            }
        }
        finally
        {
            if (queryPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(queryPtr);
            }
            CloseHandle(handle);
        }
    }

    public static int GetStorageDeviceBusType(string rootPath)
    {
        if (String.IsNullOrWhiteSpace(rootPath))
        {
            return -1;
        }

        string drive = rootPath.TrimEnd('\\');
        string devicePath = @"\\.\" + drive;
        IntPtr handle = CreateFile(devicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle == INVALID_HANDLE_VALUE)
        {
            handle = CreateFile(devicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        }
        if (handle == INVALID_HANDLE_VALUE)
        {
            return -1;
        }

        IntPtr queryPtr = IntPtr.Zero;
        try
        {
            STORAGE_PROPERTY_QUERY query = new STORAGE_PROPERTY_QUERY();
            query.PropertyId = 0;
            query.QueryType = 0;
            int querySize = Marshal.SizeOf(typeof(STORAGE_PROPERTY_QUERY));
            queryPtr = Marshal.AllocHGlobal(querySize);
            Marshal.StructureToPtr(query, queryPtr, false);

            byte[] output = new byte[4096];
            int bytesReturned;
            if (!DeviceIoControl(handle, IOCTL_STORAGE_QUERY_PROPERTY, queryPtr, querySize, output, output.Length, out bytesReturned, IntPtr.Zero))
            {
                return -1;
            }

            GCHandle pinned = GCHandle.Alloc(output, GCHandleType.Pinned);
            try
            {
                STORAGE_DEVICE_DESCRIPTOR descriptor = (STORAGE_DEVICE_DESCRIPTOR)Marshal.PtrToStructure(pinned.AddrOfPinnedObject(), typeof(STORAGE_DEVICE_DESCRIPTOR));
                return descriptor.BusType;
            }
            finally
            {
                pinned.Free();
            }
        }
        finally
        {
            if (queryPtr != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(queryPtr);
            }
            CloseHandle(handle);
        }
    }
}
"@

$ErrorActionPreference = "Stop"

$script:IsChineseUi = [System.Globalization.CultureInfo]::CurrentUICulture.Name.StartsWith("zh", [System.StringComparison]::OrdinalIgnoreCase)
$script:UiText = @{
    en = @{
        AppName = "Plug & Backup"
        ChooseBackupFolder = "Choose the folder where USB photos and videos should be backed up."
        ChooseBackupBeforeStart = "Please choose a backup folder before USB backup can start."
        BackupFolderNotWritable = "The backup folder is not writable. Please choose another folder."
        ChooseWritableBackupFolder = "Choose a writable backup folder."
        BackupRootUnavailableTitle = "Backup folder unavailable"
        BackupRootUnavailableMessage = "The configured backup folder is offline or not writable.`r`n`r`nBackup folder:`r`n{0}`r`n`r`nDrive waiting for backup:`r`n{1}`r`n`r`nChoose another backup folder to continue, or skip backup for this device until it is unplugged and inserted again."
        SkipBackupForNow = "Skip backup for now"
        ChooseAnotherBackupFolder = "Choose another backup folder"
        NoLabel = "(no label)"
        TrustMessage = "Trust this drive for automatic photo and video backup?`r`n`r`nDrive: {0}`r`nLabel: {1}`r`n`r`nNo files will be written to the card or drive."
        PossibleTrustMessage = "This looks like a previously trusted source, but some identifiers changed.`r`n`r`nDrive: {0}`r`nLabel: {1}`r`nMatched source: {2}`r`n`r`nTrust this source and update its local fingerprint?"
        CrossConnectionTrustMessage = "This may be the same memory card connected through a different camera, card reader, or USB mode.`r`n`r`nDrive: {0}`r`nLabel: {1}`r`nMatched source: {2}`r`n`r`nTrust this connection as the same source? No files will be written to the card."
        TrustAndBackup = "Trust and back up"
        SkipThisTime = "Skip this time"
        AlwaysSkip = "Always skip"
        SkippedSourceSaved = "This source will always be skipped."
        TrustedNotice = "Trusted {0}. Backup will start now."
        TrustedNoticeConfirmMode = "Trusted {0}. Confirm the next prompt to start backup."
        BackingUpNotice = "Backing up {0} file(s) from {1}"
        BackupSummary = "Copied {0}, skipped {1}, failed {2} from {3}"
        BackupSummaryWithFolder = "Copied {0}, skipped {1}, failed {2} from {3}`r`nBackup folder: {4}"
        NoMediaNotice = "No supported photos or videos were found on {0}."
        ScanFailedNotice = "Backup scan failed. Check the log."
        ScanNow = "Scan now"
        OpenBackupFolder = "Open backup folder"
        OpenRecentBackupFolder = "Open recent backup folder"
        NoRecentBackupFolder = "No recent backup folder is available yet."
        ChangeBackupFolder = "Change backup folder"
        ChooseNewBackupFolder = "Choose the new backup folder."
        BackupFolderUpdated = "Backup folder updated."
        EditExtensions = "Edit supported formats"
        EditExtensionsPrompt = "Enter file extensions to back up. You can use one extension per line, or separate them with commas or spaces."
        EditExtensionsExample = "Example: jpg, mp4, arw"
        ExtensionsUpdated = "Supported formats updated."
        ExtensionsInvalid = "No valid file extensions were entered."
        Save = "Save"
        Cancel = "Cancel"
        Settings = "Settings"
        Continue = "Continue"
        StartWithWindows = "Start with Windows"
        AutoScanOnStartup = "Scan connected devices when the app starts"
        SplitByMediaType = "Separate Photos / Videos / RAW folders"
        GroupBySourceDevice = "Separate folders by device"
        PreserveSourceStructure = "Preserve source folder structure"
        OpenFolderAfterBackup = "Open backup folder after backup"
        MinFileSizeLabel = "Minimum file size (KB)"
        ExcludedFolders = "Excluded folders"
        EditExcludedFoldersPrompt = "Enter folder names to skip. Use one folder per line, or separate names with commas."
        ExcludedFoldersUpdated = "Excluded folders updated."
        BackupHistory = "Backup history"
        LastBackupResult = "Recent backup result"
        NoBackupHistory = "No backup result has been recorded yet."
        About = "About"
        AboutText = "Plug & Backup {0}`r`n`r`nConfig:`r`n{1}`r`n`r`nState and logs:`r`n{2}`r`n`r`nLog:`r`n{3}"
        ExportDiagnostics = "Export diagnostics"
        DiagnosticsExported = "Diagnostics were exported and copied to the clipboard:`r`n{0}"
        OpenLogFolder = "Open log folder"
        RunSetupAgain = "Run setup again"
        SetupUpdated = "Setup updated."
        LastBackupText = "Time: {0}`r`nSource: {1}`r`nCopied: {2}`r`nSkipped: {3}`r`nFailed: {4}`r`nTotal: {5}`r`nBackup folder: {6}`r`nStatus: {7}"
        StatusCompleted = "Completed"
        StatusNoMedia = "No media files found"
        StatusSkipped = "Skipped"
        StatusFailed = "Failed"
        MuteNotificationSound = "Mute notification sound"
        EnableAutomaticProcessing = "Enable automatic processing"
        BackupStartModeSetting = "Backup start mode"
        ModeAutomaticOption = "Back up automatically"
        ModeConfirmOption = "Ask before backing up after insert"
        UnknownDeviceFolder = "Unknown device"
        BackupFolderLabel = "Backup folder"
        Browse = "Browse..."
        Close = "Close"
        SettingsSaved = "Settings saved."
        ViewLog = "View log"
        PauseAutoBackup = "Pause automatic backup"
        ResumeAutoBackup = "Resume automatic backup"
        AutoBackupPaused = "Automatic backup is paused."
        AutoBackupResumed = "Automatic backup resumed."
        BackupModeAutomatic = "Backup mode: automatic"
        BackupModeConfirmBeforeBackup = "Backup mode: confirm after insert"
        BackupModeSetAutomatic = "Backup mode set to automatic backup."
        BackupModeSetConfirmBeforeBackup = "Backup mode set to confirm after insert."
        ConfirmBackupStart = "Start backup from this drive now?`r`n`r`nDrive: {0}`r`nLabel: {1}`r`n`r`nChoose No to skip backup until this device is unplugged and inserted again."
        ShowBackupSummary = "Show backup summary"
        ManageTrustedSources = "Manage trusted/skipped sources"
        TrustedSourcesHeader = "Trusted"
        IgnoredSourcesHeader = "Skipped"
        NoTrustedSources = "No trusted or skipped sources have been saved yet."
        TrustedSourcesPrompt = "Enter a source id to remove, such as T1 or S1, or leave blank to cancel:`r`n`r`n{0}"
        RemoveTrustedSourceConfirm = "Remove this saved source?`r`n`r`n{0}`r`n`r`nBacked-up files will not be deleted."
        TrustedSourceRemoved = "Saved source removed."
        InvalidTrustedSourceChoice = "No matching source id was entered."
        OpenConfigFolder = "Open config folder"
        CleanupData = "Clean up / uninstall data"
        CleanupConfirm = "This will remove local app data for Plug & Backup:`r`n`r`n- Settings`r`n- Logs`r`n- Duplicate index`r`n- Startup shortcut`r`n`r`nIt will NOT delete backed-up photos or videos, and it will NOT change USB drive marker files.`r`n`r`nContinue?"
        CleanupSecondConfirm = "Second confirmation:`r`n`r`nLocal settings, logs, trusted source fingerprints, custom formats, duplicate index, and startup shortcut will be deleted from this computer.`r`n`r`nBacked-up photos and videos will remain untouched.`r`n`r`nDelete local app data now?"
        CleanupComplete = "Local app data has been removed. Backed-up photos and videos were not deleted."
        CleanupFailed = "Cleanup failed: {0}"
        Exit = "Exit"
        AlreadyRunning = "Plug & Backup is already running."
        RunningInTray = "Plug & Backup is running in the system tray."
    }
    zh = @{
        AppName = "随插备份"
        ChooseBackupFolder = "请选择用于备份 USB 照片和视频的文件夹。"
        ChooseBackupBeforeStart = "开始 USB 备份前，请先选择一个备份文件夹。"
        BackupFolderNotWritable = "当前备份文件夹不可写，请选择另一个文件夹。"
        ChooseWritableBackupFolder = "请选择一个可写的备份文件夹。"
        BackupRootUnavailableTitle = "备份文件夹不可用"
        BackupRootUnavailableMessage = "当前设置的备份文件夹离线或不可写。`r`n`r`n备份文件夹：`r`n{0}`r`n`r`n等待备份的磁盘：`r`n{1}`r`n`r`n可以重新选择备份位置继续，也可以暂不备份此设备，直到拔出后重新插入。"
        SkipBackupForNow = "暂不备份"
        ChooseAnotherBackupFolder = "重新选择备份位置"
        NoLabel = "（无卷标）"
        TrustMessage = "是否信任此磁盘，并用于自动备份照片和视频？`r`n`r`n磁盘：{0}`r`n卷标：{1}`r`n`r`n不会向内存卡或磁盘写入任何文件。"
        PossibleTrustMessage = "这看起来像之前信任过的来源，但部分标识发生了变化。`r`n`r`n磁盘：{0}`r`n卷标：{1}`r`n匹配来源：{2}`r`n`r`n是否信任此来源并更新本机指纹？"
        CrossConnectionTrustMessage = "这可能是同一张内存卡通过不同相机、读卡器或 USB 模式连接。`r`n`r`n磁盘：{0}`r`n卷标：{1}`r`n匹配来源：{2}`r`n`r`n是否将此连接方式作为同一来源信任？不会向内存卡写入任何文件。"
        TrustAndBackup = "信任并备份"
        SkipThisTime = "本次跳过"
        AlwaysSkip = "永久跳过"
        SkippedSourceSaved = "此来源以后将自动跳过。"
        TrustedNotice = "已信任 {0}，现在开始备份。"
        TrustedNoticeConfirmMode = "已信任 {0}，请在下一步确认是否开始备份。"
        BackingUpNotice = "正在从 {1} 备份 {0} 个文件"
        BackupSummary = "已复制 {0} 个，跳过 {1} 个，失败 {2} 个，来源 {3}"
        BackupSummaryWithFolder = "已复制 {0} 个，跳过 {1} 个，失败 {2} 个，来源 {3}`r`n备份位置：{4}"
        NoMediaNotice = "在 {0} 中没有找到支持的照片或视频文件。"
        ScanFailedNotice = "备份扫描失败，请查看日志。"
        ScanNow = "立即扫描"
        OpenBackupFolder = "打开备份文件夹"
        OpenRecentBackupFolder = "打开最近备份位置"
        NoRecentBackupFolder = "还没有可打开的最近备份位置。"
        ChangeBackupFolder = "更改备份文件夹"
        ChooseNewBackupFolder = "请选择新的备份文件夹。"
        BackupFolderUpdated = "备份文件夹已更新。"
        EditExtensions = "编辑支持格式"
        EditExtensionsPrompt = "请输入要备份的文件扩展名。可以一行一个，也可以用逗号或空格分隔。"
        EditExtensionsExample = "例如：jpg, mp4, arw"
        ExtensionsUpdated = "支持格式已更新。"
        ExtensionsInvalid = "没有输入有效的文件扩展名。"
        Save = "保存"
        Cancel = "取消"
        Settings = "设置"
        Continue = "继续"
        StartWithWindows = "开机启动"
        AutoScanOnStartup = "启动时自动检查已连接设备"
        SplitByMediaType = "按照片 / 视频 / RAW 分目录"
        GroupBySourceDevice = "按设备分文件夹保存"
        PreserveSourceStructure = "保留原设备目录结构"
        OpenFolderAfterBackup = "备份完成后自动打开文件夹"
        MinFileSizeLabel = "最小文件大小（KB）"
        ExcludedFolders = "排除文件夹"
        EditExcludedFoldersPrompt = "请输入要跳过的文件夹名称。可以一行一个，也可以用逗号分隔。"
        ExcludedFoldersUpdated = "排除文件夹已更新。"
        BackupHistory = "备份历史"
        LastBackupResult = "最近备份结果"
        NoBackupHistory = "还没有记录任何备份结果。"
        About = "关于"
        AboutText = "随插备份 {0}`r`n`r`n配置：`r`n{1}`r`n`r`n状态和日志：`r`n{2}`r`n`r`n日志：`r`n{3}"
        ExportDiagnostics = "导出诊断信息"
        DiagnosticsExported = "诊断信息已导出，并已复制到剪贴板：`r`n{0}"
        OpenLogFolder = "打开日志文件夹"
        RunSetupAgain = "重新运行首次设置"
        SetupUpdated = "初始设置已更新。"
        LastBackupText = "时间：{0}`r`n来源：{1}`r`n已复制：{2}`r`n已跳过：{3}`r`n失败：{4}`r`n总数：{5}`r`n备份位置：{6}`r`n状态：{7}"
        StatusCompleted = "完成"
        StatusNoMedia = "没有找到媒体文件"
        StatusSkipped = "已跳过"
        StatusFailed = "失败"
        MuteNotificationSound = "系统通知静音"
        EnableAutomaticProcessing = "启用自动处理"
        BackupStartModeSetting = "备份启动模式"
        ModeAutomaticOption = "自动备份"
        ModeConfirmOption = "插入后先确认再备份"
        UnknownDeviceFolder = "未知设备"
        BackupFolderLabel = "备份文件夹"
        Browse = "浏览..."
        Close = "关闭"
        SettingsSaved = "设置已保存。"
        ViewLog = "查看日志"
        PauseAutoBackup = "暂停自动备份"
        ResumeAutoBackup = "恢复自动备份"
        AutoBackupPaused = "自动备份已暂停。"
        AutoBackupResumed = "自动备份已恢复。"
        BackupModeAutomatic = "备份模式：自动备份"
        BackupModeConfirmBeforeBackup = "备份模式：插入后确认"
        BackupModeSetAutomatic = "备份模式已设为自动备份。"
        BackupModeSetConfirmBeforeBackup = "备份模式已设为插入后确认。"
        ConfirmBackupStart = "现在要开始备份这个磁盘吗？`r`n`r`n磁盘：{0}`r`n卷标：{1}`r`n`r`n选择否后，本次插入期间不会再次询问；拔出后重新插入才会再次询问。"
        ShowBackupSummary = "备份完成后显示摘要"
        ManageTrustedSources = "管理信任/跳过来源"
        TrustedSourcesHeader = "信任来源"
        IgnoredSourcesHeader = "跳过来源"
        NoTrustedSources = "还没有保存任何信任或跳过来源。"
        TrustedSourcesPrompt = "请输入要删除的来源编号，例如 T1 或 S1，留空则取消：`r`n`r`n{0}"
        RemoveTrustedSourceConfirm = "要删除这个已保存来源吗？`r`n`r`n{0}`r`n`r`n已备份文件不会被删除。"
        TrustedSourceRemoved = "已保存来源已删除。"
        InvalidTrustedSourceChoice = "没有输入有效的来源编号。"
        OpenConfigFolder = "打开配置文件夹"
        CleanupData = "清理/卸载数据"
        CleanupConfirm = "这将删除随插备份的本机数据：`r`n`r`n- 配置信息`r`n- 日志`r`n- 去重索引`r`n- 开机启动快捷方式`r`n`r`n不会删除已备份的照片或视频，也不会修改 USB 设备上的标记文件。`r`n`r`n是否继续？"
        CleanupSecondConfirm = "二次确认：`r`n`r`n将从这台电脑删除本工具的本机设置、日志、已信任来源指纹、自定义格式、去重索引和开机启动快捷方式。`r`n`r`n已备份的照片和视频不会被删除。`r`n`r`n现在删除本机应用数据吗？"
        CleanupComplete = "本机应用数据已清理。已备份的照片和视频没有被删除。"
        CleanupFailed = "清理失败：{0}"
        Exit = "退出"
        AlreadyRunning = "随插备份已经在运行。"
        RunningInTray = "随插备份正在系统托盘中运行。"
    }
}

function T {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$FormatArgs
    )

    $language = if ($script:IsChineseUi) { "zh" } else { "en" }
    $template = $script:UiText[$language][$Key]
    if ($null -eq $template) {
        $template = $script:UiText.en[$Key]
    }
    if ($null -eq $template) {
        return $Key
    }
    if ($FormatArgs -ne $null -and $FormatArgs.Count -gt 0) {
        return ($template -f $FormatArgs)
    }
    return $template
}

$AppName = T "AppName"
$AppVersion = "1.0.0"
$MarkerFileName = ".usb-photo-backup-device.json"
$PhotoExtensions = @(".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif", ".bmp", ".tif", ".tiff")
$VideoExtensions = @(".mp4", ".mov", ".avi", ".mkv", ".m4v", ".3gp", ".wmv", ".mts", ".m2ts")
$RawExtensions = @(".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2", ".pef", ".sr2", ".x3f", ".crw", ".iiq", ".3fr")
$DefaultExtensions = @(
    $PhotoExtensions + $VideoExtensions + $RawExtensions
)
$script:SupportedExtensions = @($DefaultExtensions)

$script:IsPackagedExe = [string]::IsNullOrWhiteSpace($PSScriptRoot)
$script:AppRoot = if ($script:IsPackagedExe) {
    try {
        $mainModulePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        Split-Path -Parent $mainModulePath
    }
    catch {
        [AppDomain]::CurrentDomain.BaseDirectory
    }
}
else {
    $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($script:AppRoot)) {
    $script:AppRoot = (Get-Location).Path
}

$AppDataRoot = if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { [Environment]::GetFolderPath("ApplicationData") } else { $env:APPDATA }
$LocalAppDataRoot = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { [Environment]::GetFolderPath("LocalApplicationData") } else { $env:LOCALAPPDATA }
if ([string]::IsNullOrWhiteSpace($AppDataRoot) -or [string]::IsNullOrWhiteSpace($LocalAppDataRoot)) {
    $userProfileRoot = [Environment]::GetFolderPath("UserProfile")
    if ([string]::IsNullOrWhiteSpace($userProfileRoot)) {
        $userProfileRoot = $env:USERPROFILE
    }
    if ([string]::IsNullOrWhiteSpace($userProfileRoot)) {
        $userProfileRoot = $script:AppRoot
    }
    if ([string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $AppDataRoot = Join-Path $userProfileRoot "AppData\Roaming"
    }
    if ([string]::IsNullOrWhiteSpace($LocalAppDataRoot)) {
        $LocalAppDataRoot = Join-Path $userProfileRoot "AppData\Local"
    }
}

$ConfigDir = Join-Path $AppDataRoot "UsbPhotoBackup"
$StateDir = Join-Path $LocalAppDataRoot "UsbPhotoBackup"
$LogDir = Join-Path $StateDir "logs"
$ConfigPath = Join-Path $ConfigDir "config.json"
$ManifestPath = Join-Path $StateDir "manifest.json"
$LastBackupResultPath = Join-Path $StateDir "last-backup.json"
$LogPath = Join-Path $LogDir "backup.log"
$IconPath = Join-Path (Join-Path $script:AppRoot "assets") "usb-backup.ico"

$script:Config = $null
$script:Manifest = $null
$script:NotifyIcon = $null
$script:ScanTimer = $null
$script:SettingsForm = $null
$script:LastBackupResult = $null
$script:IsScanning = $false
$script:IgnoredRoots = @{}
$script:CurrentRoots = @{}
$script:SkippedFixedDriveCache = @{}

function Ensure-Directory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Directory path is empty."
    }

    if (-not [System.IO.Directory]::Exists($Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")][string]$Level = "INFO"
    )

    Ensure-Directory -Path $LogDir
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Get-NotifyIconNativeInfo {
    if ($script:NotifyIcon -eq $null) {
        return $null
    }

    try {
        $flags = [System.Reflection.BindingFlags]"NonPublic,Instance"
        $notifyIconType = $script:NotifyIcon.GetType()
        $idField = $notifyIconType.GetField("id", $flags)
        $windowField = $notifyIconType.GetField("window", $flags)
        if ($idField -eq $null -or $windowField -eq $null) {
            return $null
        }

        $window = $windowField.GetValue($script:NotifyIcon)
        if ($window -eq $null) {
            return $null
        }

        return [pscustomobject]@{
            Handle = $window.Handle
            Id = [int]$idField.GetValue($script:NotifyIcon)
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to read native notification handle: $($_.Exception.Message)"
        return $null
    }
}

function ConvertTo-NativeToolTipIcon {
    param([System.Windows.Forms.ToolTipIcon]$Icon)

    switch ($Icon) {
        ([System.Windows.Forms.ToolTipIcon]::Info) { return 1 }
        ([System.Windows.Forms.ToolTipIcon]::Warning) { return 2 }
        ([System.Windows.Forms.ToolTipIcon]::Error) { return 3 }
        default { return 0 }
    }
}

function Show-Notice {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Text,
        [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
    )

    if ($script:NotifyIcon -ne $null) {
        $script:NotifyIcon.BalloonTipTitle = $Title
        $script:NotifyIcon.BalloonTipText = $Text
        $script:NotifyIcon.BalloonTipIcon = $Icon
        if ($script:Config -ne $null -and (Test-ObjectProperty -Object $script:Config -Name "MuteNotificationSound") -and [bool]$script:Config.MuteNotificationSound) {
            $nativeInfo = Get-NotifyIconNativeInfo
            if ($nativeInfo -ne $null -and [UsbPhotoBackupNative]::ShowSilentBalloon($nativeInfo.Handle, $nativeInfo.Id, $Title, $Text, (ConvertTo-NativeToolTipIcon -Icon $Icon), 5000)) {
                return
            }
        }

        $script:NotifyIcon.ShowBalloonTip(5000)
    }
}

function Read-JsonFile {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)]$DefaultValue
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $DefaultValue
    }

    if (-not [System.IO.File]::Exists($Path)) {
        return $DefaultValue
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $DefaultValue
        }
        return ($raw | ConvertFrom-Json)
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to read JSON file '$Path': $($_.Exception.Message)"
        return $DefaultValue
    }
}

function Save-JsonFile {
    param(
        [string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "JSON path is empty."
    }

    $parent = Split-Path -Parent $Path
    Ensure-Directory -Path $parent
    $json = $Value | ConvertTo-Json -Depth 10
    $tempPath = Join-Path $parent ("{0}.{1}.tmp" -f ([System.IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    $backupPath = Join-Path $parent ("{0}.{1}.bak" -f ([System.IO.Path]::GetFileName($Path)), [Guid]::NewGuid().ToString("N"))
    try {
        Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8
        if ([System.IO.File]::Exists($Path)) {
            [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }
    }
    catch {
        if ([System.IO.File]::Exists($tempPath)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if ([System.IO.File]::Exists($backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function New-DefaultConfig {
    return [pscustomobject]@{
        BackupRoot = $null
        TrustedDeviceIds = @()
        TrustedSources = @()
        IgnoredSources = @()
        FileExtensions = @($DefaultExtensions)
        AutoBackupEnabled = $true
        BackupStartMode = "Automatic"
        ShowBackupSummary = $true
        MuteNotificationSound = $false
        AutoScanOnStartup = $true
        SplitByMediaType = $false
        GroupBySourceDevice = $false
        PreserveSourceStructure = $false
        OpenFolderAfterBackup = $false
        MinFileSizeBytes = 0
        ExcludedFolders = @("System Volume Information", "`$RECYCLE.BIN")
        ScanIntervalSeconds = 8
    }
}

function ConvertTo-StringArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ }
}

function Normalize-Extensions {
    param($Extensions)

    $items = @()
    foreach ($value in @(ConvertTo-StringArray $Extensions)) {
        foreach ($part in ($value -split '[,;\s]+')) {
            $extension = ([string]$part).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($extension)) {
                continue
            }
            if (-not $extension.StartsWith(".")) {
                $extension = ".$extension"
            }
            if ($extension -match '^\.[a-z0-9]{1,12}$') {
                $items += $extension
            }
        }
    }

    return @($items | Sort-Object -Unique)
}

function ConvertTo-NonNegativeInt64 {
    param(
        $Value,
        [int64]$DefaultValue = 0
    )

    try {
        return [Math]::Max(0, [int64]$Value)
    }
    catch {
        return $DefaultValue
    }
}

function Load-Config {
    Ensure-Directory -Path $ConfigDir
    Ensure-Directory -Path $StateDir
    Ensure-Directory -Path $LogDir

    $config = Read-JsonFile -Path $ConfigPath -DefaultValue (New-DefaultConfig)
    if (-not (Test-ObjectProperty -Object $config -Name "BackupRoot")) {
        $config | Add-Member -MemberType NoteProperty -Name BackupRoot -Value $null
    }
    if (-not (Test-ObjectProperty -Object $config -Name "TrustedDeviceIds")) {
        $config | Add-Member -MemberType NoteProperty -Name TrustedDeviceIds -Value @()
    }
    if (-not (Test-ObjectProperty -Object $config -Name "TrustedSources")) {
        $config | Add-Member -MemberType NoteProperty -Name TrustedSources -Value @()
    }
    if (-not (Test-ObjectProperty -Object $config -Name "IgnoredSources")) {
        $config | Add-Member -MemberType NoteProperty -Name IgnoredSources -Value @()
    }
    if (-not (Test-ObjectProperty -Object $config -Name "FileExtensions")) {
        $config | Add-Member -MemberType NoteProperty -Name FileExtensions -Value @($DefaultExtensions)
    }
    if (-not (Test-ObjectProperty -Object $config -Name "AutoBackupEnabled")) {
        $config | Add-Member -MemberType NoteProperty -Name AutoBackupEnabled -Value $true
    }
    if (-not (Test-ObjectProperty -Object $config -Name "BackupStartMode")) {
        $config | Add-Member -MemberType NoteProperty -Name BackupStartMode -Value "Automatic"
    }
    if (-not (Test-ObjectProperty -Object $config -Name "ShowBackupSummary")) {
        $config | Add-Member -MemberType NoteProperty -Name ShowBackupSummary -Value $true
    }
    if (-not (Test-ObjectProperty -Object $config -Name "MuteNotificationSound")) {
        $config | Add-Member -MemberType NoteProperty -Name MuteNotificationSound -Value $false
    }
    if (-not (Test-ObjectProperty -Object $config -Name "AutoScanOnStartup")) {
        $config | Add-Member -MemberType NoteProperty -Name AutoScanOnStartup -Value $true
    }
    if (-not (Test-ObjectProperty -Object $config -Name "SplitByMediaType")) {
        $config | Add-Member -MemberType NoteProperty -Name SplitByMediaType -Value $false
    }
    if (-not (Test-ObjectProperty -Object $config -Name "GroupBySourceDevice")) {
        $config | Add-Member -MemberType NoteProperty -Name GroupBySourceDevice -Value $false
    }
    if (-not (Test-ObjectProperty -Object $config -Name "PreserveSourceStructure")) {
        $config | Add-Member -MemberType NoteProperty -Name PreserveSourceStructure -Value $false
    }
    if (-not (Test-ObjectProperty -Object $config -Name "OpenFolderAfterBackup")) {
        $config | Add-Member -MemberType NoteProperty -Name OpenFolderAfterBackup -Value $false
    }
    if (-not (Test-ObjectProperty -Object $config -Name "MinFileSizeBytes")) {
        $config | Add-Member -MemberType NoteProperty -Name MinFileSizeBytes -Value 0
    }
    if (-not (Test-ObjectProperty -Object $config -Name "ExcludedFolders")) {
        $config | Add-Member -MemberType NoteProperty -Name ExcludedFolders -Value @("System Volume Information", "`$RECYCLE.BIN")
    }
    if (-not (Test-ObjectProperty -Object $config -Name "ScanIntervalSeconds")) {
        $config | Add-Member -MemberType NoteProperty -Name ScanIntervalSeconds -Value 8
    }

    $config.TrustedDeviceIds = @(ConvertTo-StringArray $config.TrustedDeviceIds)
    $config.TrustedSources = @($config.TrustedSources)
    $config.IgnoredSources = @($config.IgnoredSources)
    $config.FileExtensions = @(Normalize-Extensions -Extensions $config.FileExtensions)
    if ($config.FileExtensions.Count -eq 0) {
        $config.FileExtensions = @($DefaultExtensions)
    }
    $script:SupportedExtensions = @($config.FileExtensions)
    $config.AutoBackupEnabled = [bool]$config.AutoBackupEnabled
    if (@("Automatic", "ConfirmBeforeBackup") -notcontains ([string]$config.BackupStartMode)) {
        $config.BackupStartMode = "Automatic"
    }
    $config.ShowBackupSummary = [bool]$config.ShowBackupSummary
    $config.MuteNotificationSound = [bool]$config.MuteNotificationSound
    $config.AutoScanOnStartup = [bool]$config.AutoScanOnStartup
    $config.SplitByMediaType = [bool]$config.SplitByMediaType
    $config.GroupBySourceDevice = [bool]$config.GroupBySourceDevice
    $config.PreserveSourceStructure = [bool]$config.PreserveSourceStructure
    $config.OpenFolderAfterBackup = [bool]$config.OpenFolderAfterBackup
    $config.MinFileSizeBytes = ConvertTo-NonNegativeInt64 -Value $config.MinFileSizeBytes
    $config.ExcludedFolders = @(ConvertTo-StringArray $config.ExcludedFolders)
    $script:Config = $config
}

function Load-Manifest {
    $default = [pscustomobject]@{
        Hashes = [pscustomobject]@{}
    }
    $manifest = Read-JsonFile -Path $ManifestPath -DefaultValue $default

    $hashes = @{}
    if (Test-ObjectProperty -Object $manifest -Name "Hashes") {
        foreach ($property in $manifest.Hashes.PSObject.Properties) {
            $hashes[$property.Name] = $property.Value
        }
    }

    $script:Manifest = [pscustomobject]@{
        Hashes = $hashes
    }
}

function Load-LastBackupResult {
    $default = [pscustomobject]@{}
    $result = Read-JsonFile -Path $LastBackupResultPath -DefaultValue $default
    if (Test-ObjectProperty -Object $result -Name "StartedAtLocal") {
        $script:LastBackupResult = $result
    }
    else {
        $script:LastBackupResult = $null
    }
}

function Save-LastBackupResult {
    param([Parameter(Mandatory = $true)]$Result)

    $script:LastBackupResult = $Result
    Save-JsonFile -Path $LastBackupResultPath -Value $Result
}

function Save-Config {
    $script:Config.TrustedDeviceIds = @(ConvertTo-StringArray $script:Config.TrustedDeviceIds)
    $script:Config.TrustedSources = @($script:Config.TrustedSources)
    $script:Config.IgnoredSources = @($script:Config.IgnoredSources)
    $script:Config.FileExtensions = @(Normalize-Extensions -Extensions $script:Config.FileExtensions)
    $script:Config.ExcludedFolders = @(ConvertTo-StringArray $script:Config.ExcludedFolders)
    $script:Config.MinFileSizeBytes = ConvertTo-NonNegativeInt64 -Value $script:Config.MinFileSizeBytes
    $script:Config.GroupBySourceDevice = [bool]$script:Config.GroupBySourceDevice
    if (@("Automatic", "ConfirmBeforeBackup") -notcontains ([string]$script:Config.BackupStartMode)) {
        $script:Config.BackupStartMode = "Automatic"
    }
    Save-JsonFile -Path $ConfigPath -Value $script:Config
}

function Save-Manifest {
    $manifestForJson = [ordered]@{
        Hashes = [ordered]@{}
    }

    foreach ($key in ($script:Manifest.Hashes.Keys | Sort-Object)) {
        $manifestForJson.Hashes[$key] = $script:Manifest.Hashes[$key]
    }

    Save-JsonFile -Path $ManifestPath -Value $manifestForJson
}

function Select-BackupRoot {
    param([string]$Description = (T "ChooseBackupFolder"))

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    $dialog.RootFolder = [System.Environment+SpecialFolder]::MyComputer
    $isFirstSetup = [string]::IsNullOrWhiteSpace($script:Config.BackupRoot)

    $selectedPath = [string]$script:Config.BackupRoot
    if (-not [string]::IsNullOrWhiteSpace($selectedPath) -and [System.IO.Directory]::Exists($selectedPath)) {
        $dialog.SelectedPath = $selectedPath
    }

    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($dialog.SelectedPath)) {
        $script:Config.BackupRoot = $dialog.SelectedPath
        Save-Config
        Write-Log -Message "Backup root set to '$($script:Config.BackupRoot)'"
        if ($isFirstSetup) {
            Open-SettingsWindow
        }
        return $true
    }

    return $false
}

function Test-BackupRootWritable {
    if ([string]::IsNullOrWhiteSpace($script:Config.BackupRoot)) {
        return $false
    }

    try {
        if (-not [System.IO.Directory]::Exists($script:Config.BackupRoot)) {
            return $false
        }

        $probe = Join-Path $script:Config.BackupRoot ".usb-photo-backup-write-test.tmp"
        Set-Content -LiteralPath $probe -Value "test" -Encoding ASCII
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch {
        Write-Log -Level "WARN" -Message "Backup root unavailable or not writable '$($script:Config.BackupRoot)': $($_.Exception.Message)"
        return $false
    }
}

function Ensure-InitialBackupRoot {
    if ([string]::IsNullOrWhiteSpace($script:Config.BackupRoot)) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "ChooseBackupBeforeStart"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        if (-not (Select-BackupRoot)) {
            return $false
        }
    }

    return $true
}

function Show-BackupRootUnavailableDialog {
    param(
        [Parameter(Mandatory = $true)][string]$DriveRoot
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "BackupRootUnavailableTitle"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 560, 210
    $form.Icon = Get-TrayIcon
    $form.Font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", 9
    $form.Tag = "Skip"

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Text = T "BackupRootUnavailableMessage" -FormatArgs @([string]$script:Config.BackupRoot, $DriveRoot)
    $messageLabel.Location = New-Object System.Drawing.Point -ArgumentList 18, 18
    $messageLabel.Size = New-Object System.Drawing.Size -ArgumentList 524, 132
    $form.Controls.Add($messageLabel)

    $chooseButton = New-Object System.Windows.Forms.Button
    $chooseButton.Text = T "ChooseAnotherBackupFolder"
    $chooseButton.Location = New-Object System.Drawing.Point -ArgumentList 286, 164
    $chooseButton.Size = New-Object System.Drawing.Size -ArgumentList 250, 32
    $chooseButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Tag = "Choose"; $sender.FindForm().Close() })
    $form.Controls.Add($chooseButton)
    $form.AcceptButton = $chooseButton

    $skipButton = New-Object System.Windows.Forms.Button
    $skipButton.Text = T "SkipBackupForNow"
    $skipButton.Location = New-Object System.Drawing.Point -ArgumentList 18, 164
    $skipButton.Size = New-Object System.Drawing.Size -ArgumentList 250, 32
    $skipButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Tag = "Skip"; $sender.FindForm().Close() })
    $form.Controls.Add($skipButton)
    $form.CancelButton = $skipButton

    [void]$form.ShowDialog()
    $decision = [string]$form.Tag
    $form.Dispose()
    return $decision
}

function Resolve-BackupRootForBackup {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $root = $Drive.RootDirectory.FullName
    if ($script:IgnoredRoots.ContainsKey($root)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:Config.BackupRoot)) {
        if (-not (Ensure-InitialBackupRoot)) {
            return $false
        }
    }

    if (Test-BackupRootWritable) {
        return $true
    }

    Write-Log -Level "WARN" -Message "Backup root unavailable before backing up '$root': '$($script:Config.BackupRoot)'"
    $decision = Show-BackupRootUnavailableDialog -DriveRoot $root
    if ($decision -ne "Choose") {
        $script:IgnoredRoots[$root] = $true
        Write-Log -Message "User skipped backup for '$root' because backup root is unavailable"
        return $false
    }

    while ($true) {
        if (-not (Select-BackupRoot -Description (T "ChooseWritableBackupFolder"))) {
            $script:IgnoredRoots[$root] = $true
            Write-Log -Message "User canceled backup folder selection for '$root'; skipping until reinsertion"
            return $false
        }

        if (Test-BackupRootWritable) {
            Write-Log -Message "Backup root changed and verified for '$root': '$($script:Config.BackupRoot)'"
            return $true
        }

        [System.Windows.Forms.MessageBox]::Show(
            (T "BackupFolderNotWritable"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Ensure-BackupRoot {
    if (-not (Ensure-InitialBackupRoot)) {
        return $false
    }

    if (Test-BackupRootWritable) {
        return $true
    }

    [System.Windows.Forms.MessageBox]::Show(
        (T "BackupFolderNotWritable"),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    return (Select-BackupRoot -Description (T "ChooseWritableBackupFolder"))
}

function Normalize-DriveRoot {
    param([string]$Root)

    if ([string]::IsNullOrWhiteSpace($Root)) {
        return $null
    }

    $normalized = $Root.Trim()
    if ($normalized -match '^[A-Za-z]:$') {
        $normalized = "$normalized\"
    }

    return $normalized
}

function Get-PathRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $root = $null
    try {
        $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path).Path)
    }
    catch {
        $root = [System.IO.Path]::GetPathRoot($Path)
    }

    return (Normalize-DriveRoot -Root $root)
}

function Get-StorageDeviceBusType {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        return [UsbPhotoBackupNative]::GetStorageDeviceBusType($Drive.RootDirectory.FullName)
    }
    catch {
        Write-Log -Level "WARN" -Message "DeviceIoControl bus type unavailable for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
        return -1
    }
}

function Test-ExternalStorageBusType {
    param([int]$BusType)

    return ($BusType -eq 7 -or $BusType -eq 12 -or $BusType -eq 13)
}

function Test-UnknownStorageBusType {
    param([int]$BusType)

    return ($BusType -lt 0 -or $BusType -eq 0)
}

function Get-FixedDriveSkipCacheKey {
    param(
        [Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive,
        [Parameter(Mandatory = $true)][int]$BusType
    )

    $root = Normalize-DriveRoot -Root $Drive.RootDirectory.FullName
    $totalSize = 0
    try {
        $totalSize = [int64]$Drive.TotalSize
    }
    catch {
        $totalSize = 0
    }

    return ("{0}|{1}|{2}" -f $root, $BusType, $totalSize)
}

function Add-SkippedFixedDriveCache {
    param(
        [Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive,
        [Parameter(Mandatory = $true)][int]$BusType
    )

    $cacheKey = Get-FixedDriveSkipCacheKey -Drive $Drive -BusType $BusType
    $root = Normalize-DriveRoot -Root $Drive.RootDirectory.FullName
    if ($script:SkippedFixedDriveCache.ContainsKey($cacheKey)) {
        $script:SkippedFixedDriveCache[$cacheKey].LastSeenAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        return $false
    }

    foreach ($existingKey in @($script:SkippedFixedDriveCache.Keys)) {
        $existingEntry = $script:SkippedFixedDriveCache[$existingKey]
        if ($existingEntry -ne $null -and [string]::Equals([string]$existingEntry.Root, $root, [System.StringComparison]::OrdinalIgnoreCase)) {
            $script:SkippedFixedDriveCache.Remove($existingKey)
        }
    }

    $totalSize = 0
    try {
        $totalSize = [int64]$Drive.TotalSize
    }
    catch {
        $totalSize = 0
    }

    $script:SkippedFixedDriveCache[$cacheKey] = [pscustomobject]@{
        Root = $root
        BusType = $BusType
        TotalSize = $totalSize
        LastSeenAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
    return $true
}

function Clear-StaleSkippedFixedDriveCache {
    param([string[]]$ReadyFixedRoots)

    $readyRoots = @{}
    foreach ($root in @($ReadyFixedRoots)) {
        $normalizedRoot = Normalize-DriveRoot -Root $root
        if (-not [string]::IsNullOrWhiteSpace($normalizedRoot)) {
            $readyRoots[$normalizedRoot] = $true
        }
    }

    foreach ($cacheKey in @($script:SkippedFixedDriveCache.Keys)) {
        $entry = $script:SkippedFixedDriveCache[$cacheKey]
        if ($entry -eq $null -or -not $readyRoots.ContainsKey([string]$entry.Root)) {
            $script:SkippedFixedDriveCache.Remove($cacheKey)
        }
    }
}

function Test-UsbAttachedFixedDrive {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $busType = Get-StorageDeviceBusType -Drive $Drive
    if (Test-ExternalStorageBusType -BusType $busType) {
        return $true
    }

    if (Test-UnknownStorageBusType -BusType $busType) {
        $hardwareInfo = Get-WmiHardwareInfo -Drive $Drive
        if ($hardwareInfo -ne $null) {
            $interfaceType = [string]$hardwareInfo.InterfaceType
            $pnpDeviceId = [string]$hardwareInfo.PNPDeviceID
            if ($interfaceType -match 'USB' -or $pnpDeviceId -match 'USBSTOR|UASPSTOR|VID_') {
                return $true
            }
        }
    }

    if (Add-SkippedFixedDriveCache -Drive $Drive -BusType $busType) {
        Write-Log -Message "Skipped fixed local drive '$($Drive.RootDirectory.FullName)' because it is not identified as USB/SD/MMC attached. BusType=$busType"
    }
    return $false
}

function Get-CandidateDrives {
    try {
        $systemRoot = Get-PathRoot -Path $env:SystemDrive
        $backupRoot = Get-PathRoot -Path $script:Config.BackupRoot
        $drives = @([System.IO.DriveInfo]::GetDrives())
        $readyFixedRoots = @(
            foreach ($drive in $drives) {
                if ($drive.IsReady -and $drive.DriveType -eq [System.IO.DriveType]::Fixed) {
                    $drive.RootDirectory.FullName
                }
            }
        )
        Clear-StaleSkippedFixedDriveCache -ReadyFixedRoots $readyFixedRoots

        $candidates = @()
        foreach ($drive in $drives) {
            if (-not $drive.IsReady) {
                continue
            }

            $root = $drive.RootDirectory.FullName
            if ($systemRoot -and [string]::Equals($root, $systemRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($backupRoot -and [string]::Equals($root, $backupRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            if ($drive.DriveType -eq [System.IO.DriveType]::Removable) {
                $candidates += $drive
                continue
            }

            if ($drive.DriveType -eq [System.IO.DriveType]::Fixed -and (Test-UsbAttachedFixedDrive -Drive $drive)) {
                $candidates += $drive
            }
        }

        return $candidates
    }
    catch {
        Write-Log -Level "ERROR" -Message "Failed to list candidate drives: $($_.Exception.Message)"
        return @()
    }
}

function Get-StringHash {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Join-FingerprintParts {
    param([string[]]$Parts)

    return (@($Parts) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "|"
}

function New-FingerprintPart {
    param(
        [string]$Name,
        $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    return ("{0}={1}" -f $Name, ([string]$Value).Trim())
}

function Get-VolumeGuid {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        $buffer = New-Object System.Text.StringBuilder 1024
        if ([UsbPhotoBackupNative]::GetVolumeNameForVolumeMountPoint($Drive.RootDirectory.FullName, $buffer, $buffer.Capacity)) {
            return $buffer.ToString().TrimEnd("\")
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to read volume GUID for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
    }

    return $null
}

function Get-NativeVolumeInfo {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        $volumeName = New-Object System.Text.StringBuilder 260
        $fileSystemName = New-Object System.Text.StringBuilder 260
        [uint32]$serial = 0
        [uint32]$maxComponentLength = 0
        [uint32]$fileSystemFlags = 0
        $ok = [UsbPhotoBackupNative]::GetVolumeInformation(
            $Drive.RootDirectory.FullName,
            $volumeName,
            $volumeName.Capacity,
            [ref]$serial,
            [ref]$maxComponentLength,
            [ref]$fileSystemFlags,
            $fileSystemName,
            $fileSystemName.Capacity
        )

        if ($ok) {
            return [pscustomobject]@{
                VolumeSerial = $serial.ToString("X8")
                VolumeName = $volumeName.ToString()
                FileSystem = $fileSystemName.ToString()
            }
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to read native volume info for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
    }

    return $null
}

function Get-DosDevicePath {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        $driveName = $Drive.RootDirectory.FullName.TrimEnd("\")
        $buffer = New-Object System.Text.StringBuilder 1024
        $length = [UsbPhotoBackupNative]::QueryDosDevice($driveName, $buffer, $buffer.Capacity)
        if ($length -gt 0) {
            return $buffer.ToString()
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to read DOS device path for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
    }

    return $null
}

function Get-StorageDeviceSerial {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        return [UsbPhotoBackupNative]::GetStorageDeviceSerial($Drive.RootDirectory.FullName)
    }
    catch {
        Write-Log -Level "WARN" -Message "DeviceIoControl serial unavailable for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
        return $null
    }
}

function Get-NativeStorageDescriptor {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        $raw = [UsbPhotoBackupNative]::GetStorageDeviceDescriptor($Drive.RootDirectory.FullName)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }

        $values = @{}
        foreach ($line in ($raw -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $values[$parts[0]] = $parts[1]
            }
        }

        $busType = $null
        if ($values.ContainsKey("BusType") -and -not [string]::IsNullOrWhiteSpace($values["BusType"])) {
            try {
                $busType = [int]$values["BusType"]
            }
            catch {
                $busType = $null
            }
        }

        $removableMedia = $null
        if ($values.ContainsKey("RemovableMedia") -and -not [string]::IsNullOrWhiteSpace($values["RemovableMedia"])) {
            try {
                $removableMedia = [bool]::Parse($values["RemovableMedia"])
            }
            catch {
                $removableMedia = $null
            }
        }

        return [pscustomobject]@{
            VendorId = if ($values.ContainsKey("VendorId")) { $values["VendorId"] } else { $null }
            ProductId = if ($values.ContainsKey("ProductId")) { $values["ProductId"] } else { $null }
            ProductRevision = if ($values.ContainsKey("ProductRevision")) { $values["ProductRevision"] } else { $null }
            SerialNumber = if ($values.ContainsKey("SerialNumber")) { $values["SerialNumber"] } else { $null }
            BusType = $busType
            RemovableMedia = $removableMedia
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Native storage descriptor unavailable for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
        return $null
    }
}

function Get-WmiHardwareInfo {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    try {
        $driveId = $Drive.RootDirectory.FullName.TrimEnd("\")
        $logicalDisk = Get-WmiObject Win32_LogicalDisk -Filter ("DeviceID='{0}'" -f $driveId) -ErrorAction Stop
        $partitions = @($logicalDisk.GetRelated("Win32_DiskPartition"))
        $disks = @()
        foreach ($partition in $partitions) {
            $disks += @($partition.GetRelated("Win32_DiskDrive"))
        }
        $disk = @($disks | Select-Object -First 1)[0]
        if ($null -ne $disk) {
            return [pscustomobject]@{
                Model = ([string]$disk.Model).Trim()
                SerialNumber = ([string]$disk.SerialNumber).Trim()
                InterfaceType = ([string]$disk.InterfaceType).Trim()
                MediaType = ([string]$disk.MediaType).Trim()
                PNPDeviceID = ([string]$disk.PNPDeviceID).Trim()
            }
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "WMI hardware info unavailable for '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
    }

    return $null
}

function New-SourceProfile {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $nativeVolumeInfo = Get-NativeVolumeInfo -Drive $Drive
    $hardwareInfo = Get-WmiHardwareInfo -Drive $Drive
    $nativeStorageDescriptor = Get-NativeStorageDescriptor -Drive $Drive
    $volumeGuid = Get-VolumeGuid -Drive $Drive
    $dosDevicePath = Get-DosDevicePath -Drive $Drive
    $storageDeviceSerial = if ($nativeStorageDescriptor -ne $null -and -not [string]::IsNullOrWhiteSpace($nativeStorageDescriptor.SerialNumber)) { $nativeStorageDescriptor.SerialNumber } else { Get-StorageDeviceSerial -Drive $Drive }
    $busType = if ($nativeStorageDescriptor -ne $null -and $nativeStorageDescriptor.BusType -ne $null) { $nativeStorageDescriptor.BusType } else { Get-StorageDeviceBusType -Drive $Drive }
    $nativeVendorId = if ($nativeStorageDescriptor -ne $null) { $nativeStorageDescriptor.VendorId } else { $null }
    $nativeProductId = if ($nativeStorageDescriptor -ne $null) { $nativeStorageDescriptor.ProductId } else { $null }
    $nativeProductRevision = if ($nativeStorageDescriptor -ne $null) { $nativeStorageDescriptor.ProductRevision } else { $null }
    $nativeRemovableMedia = if ($nativeStorageDescriptor -ne $null) { $nativeStorageDescriptor.RemovableMedia } else { $null }
    $fileSystem = if ($nativeVolumeInfo -ne $null -and -not [string]::IsNullOrWhiteSpace($nativeVolumeInfo.FileSystem)) { $nativeVolumeInfo.FileSystem } else { $Drive.DriveFormat }
    $volumeSerial = if ($nativeVolumeInfo -ne $null) { $nativeVolumeInfo.VolumeSerial } else { $null }
    $volumeLabel = $Drive.VolumeLabel
    $displayName = if ([string]::IsNullOrWhiteSpace($volumeLabel)) { $Drive.RootDirectory.FullName } else { $volumeLabel }

    $hardwareSerial = if ($hardwareInfo -ne $null) { $hardwareInfo.SerialNumber } else { $null }
    $hardwarePnpDeviceId = if ($hardwareInfo -ne $null) { $hardwareInfo.PNPDeviceID } else { $null }
    $hardwareModel = if ($hardwareInfo -ne $null) { $hardwareInfo.Model } else { $null }
    $hardwareInterface = if ($hardwareInfo -ne $null) { $hardwareInfo.InterfaceType } else { $null }
    $hardwareMediaType = if ($hardwareInfo -ne $null) { $hardwareInfo.MediaType } else { $null }

    $strongParts = @(
        (New-FingerprintPart "storageDeviceSerial" $storageDeviceSerial),
        (New-FingerprintPart "nativeVendorId" $nativeVendorId),
        (New-FingerprintPart "nativeProductId" $nativeProductId),
        (New-FingerprintPart "nativeProductRevision" $nativeProductRevision),
        (New-FingerprintPart "hardwareSerial" $hardwareSerial),
        (New-FingerprintPart "pnpDeviceId" $hardwarePnpDeviceId)
    )
    $mediumParts = @(
        (New-FingerprintPart "volumeGuid" $volumeGuid)
    )
    $weakParts = @(
        (New-FingerprintPart "fileSystem" $fileSystem),
        (New-FingerprintPart "totalSize" $Drive.TotalSize),
        (New-FingerprintPart "driveType" $Drive.DriveType)
    )
    $sourceIdentityParts = @(
        $strongParts + $mediumParts + @(
            (New-FingerprintPart "totalSize" $Drive.TotalSize),
            (New-FingerprintPart "driveType" $Drive.DriveType)
        )
    )
    $volumeStateParts = @(
        (New-FingerprintPart "volumeSerial" $volumeSerial),
        (New-FingerprintPart "fileSystem" $fileSystem),
        (New-FingerprintPart "volumeLabel" $volumeLabel),
        (New-FingerprintPart "dosDevicePath" $dosDevicePath)
    )
    $crossConnectionParts = @(
        (New-FingerprintPart "volumeSerial" $volumeSerial),
        (New-FingerprintPart "fileSystem" $fileSystem),
        (New-FingerprintPart "totalSize" $Drive.TotalSize),
        (New-FingerprintPart "driveType" $Drive.DriveType)
    )
    $sourceIdentityHash = Get-StringHash (Join-FingerprintParts $sourceIdentityParts)
    $volumeStateHash = Get-StringHash (Join-FingerprintParts $volumeStateParts)
    $crossConnectionHash = Get-StringHash (Join-FingerprintParts $crossConnectionParts)

    return [pscustomobject]@{
        DisplayName = $displayName
        Root = $Drive.RootDirectory.FullName
        VolumeLabel = $volumeLabel
        VolumeGuid = $volumeGuid
        VolumeSerial = $volumeSerial
        FileSystem = $fileSystem
        TotalSize = $Drive.TotalSize
        DriveType = [string]$Drive.DriveType
        BusType = $busType
        DosDevicePath = $dosDevicePath
        StorageDeviceSerial = $storageDeviceSerial
        NativeVendorId = $nativeVendorId
        NativeProductId = $nativeProductId
        NativeProductRevision = $nativeProductRevision
        NativeRemovableMedia = $nativeRemovableMedia
        HardwareModel = $hardwareModel
        HardwareSerial = $hardwareSerial
        HardwareInterface = $hardwareInterface
        HardwareMediaType = $hardwareMediaType
        HardwarePnpDeviceId = $hardwarePnpDeviceId
        StrongHash = Get-StringHash (Join-FingerprintParts $strongParts)
        MediumHash = Get-StringHash (Join-FingerprintParts $mediumParts)
        WeakHash = Get-StringHash (Join-FingerprintParts $weakParts)
        SourceIdentityHash = $sourceIdentityHash
        VolumeStateHash = $volumeStateHash
        CrossConnectionHash = $crossConnectionHash
        FingerprintHash = $sourceIdentityHash
        Components = [pscustomobject]@{
            Strong = @(Join-FingerprintParts $strongParts)
            Medium = @(Join-FingerprintParts $mediumParts)
            Weak = @(Join-FingerprintParts $weakParts)
            SourceIdentity = @(Join-FingerprintParts $sourceIdentityParts)
            VolumeState = @(Join-FingerprintParts $volumeStateParts)
            CrossConnection = @(Join-FingerprintParts $crossConnectionParts)
        }
    }
}

function Get-MarkerPath {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)
    return (Join-Path $Drive.RootDirectory.FullName $MarkerFileName)
}

function Read-DeviceMarker {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $path = Get-MarkerPath -Drive $Drive
    if (-not [System.IO.File]::Exists($path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        Write-Log -Level "WARN" -Message "Invalid marker on '$($Drive.RootDirectory.FullName)': $($_.Exception.Message)"
        return $null
    }
}

function Test-TrustedDevice {
    param([Parameter(Mandatory = $true)][string]$DeviceId)
    return (@(ConvertTo-StringArray $script:Config.TrustedDeviceIds) -contains $DeviceId)
}

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    if (Test-ObjectProperty -Object $Object -Name $Name) {
        $Object.$Name = $Value
    }
    else {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Test-ObjectProperty {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $false
    }

    return ($Object.PSObject.Properties.Match($Name).Count -gt 0)
}

function Get-ObjectPropertyValue {
    param(
        $Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if (Test-ObjectProperty -Object $Object -Name $Name) {
        return $Object.$Name
    }

    return $DefaultValue
}

function Merge-UniqueTextValues {
    param($Values)

    $items = @()
    foreach ($value in @($Values)) {
        foreach ($item in @(ConvertTo-StringArray $value)) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $items += $item
            }
        }
    }

    return @($items | Select-Object -Unique)
}

function New-TrustedSourceRecord {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [string]$LegacyDeviceId
    )

    return [pscustomobject]@{
        Name = $Profile.DisplayName
        SourceIdentityHash = $Profile.SourceIdentityHash
        SourceIdentityHashes = @(Merge-UniqueTextValues @($Profile.SourceIdentityHash))
        VolumeStateHash = $Profile.VolumeStateHash
        CrossConnectionHash = $Profile.CrossConnectionHash
        FingerprintHash = $Profile.FingerprintHash
        StrongHash = $Profile.StrongHash
        MediumHash = $Profile.MediumHash
        WeakHash = $Profile.WeakHash
        VolumeGuid = $Profile.VolumeGuid
        VolumeSerial = $Profile.VolumeSerial
        FileSystem = $Profile.FileSystem
        TotalSize = $Profile.TotalSize
        DriveType = $Profile.DriveType
        BusType = $Profile.BusType
        StorageDeviceSerial = $Profile.StorageDeviceSerial
        NativeVendorId = $Profile.NativeVendorId
        NativeProductId = $Profile.NativeProductId
        NativeProductRevision = $Profile.NativeProductRevision
        NativeRemovableMedia = $Profile.NativeRemovableMedia
        HardwareSerial = $Profile.HardwareSerial
        HardwarePnpDeviceId = $Profile.HardwarePnpDeviceId
        HardwareModel = $Profile.HardwareModel
        HardwareInterface = $Profile.HardwareInterface
        HardwareMediaType = $Profile.HardwareMediaType
        LastDosDevicePath = $Profile.DosDevicePath
        LastVolumeLabel = $Profile.VolumeLabel
        Components = $Profile.Components
        LastRoot = $Profile.Root
        LastSeenAtUtc = [DateTime]::UtcNow.ToString("o")
        LegacyDeviceId = $LegacyDeviceId
    }
}

function Save-TrustedSource {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        $ExistingSource = $null,
        [string]$LegacyDeviceId
    )

    if ($ExistingSource -ne $null) {
        $sourceIdentityHashes = Merge-UniqueTextValues @(
            (Get-ObjectPropertyValue -Object $ExistingSource -Name "SourceIdentityHashes"),
            (Get-ObjectPropertyValue -Object $ExistingSource -Name "SourceIdentityHash"),
            (Get-ObjectPropertyValue -Object $ExistingSource -Name "FingerprintHash"),
            $Profile.SourceIdentityHash
        )

        Set-ObjectProperty -Object $ExistingSource -Name Name -Value $Profile.DisplayName
        Set-ObjectProperty -Object $ExistingSource -Name SourceIdentityHash -Value $Profile.SourceIdentityHash
        Set-ObjectProperty -Object $ExistingSource -Name SourceIdentityHashes -Value @($sourceIdentityHashes)
        Set-ObjectProperty -Object $ExistingSource -Name VolumeStateHash -Value $Profile.VolumeStateHash
        Set-ObjectProperty -Object $ExistingSource -Name CrossConnectionHash -Value $Profile.CrossConnectionHash
        Set-ObjectProperty -Object $ExistingSource -Name FingerprintHash -Value $Profile.FingerprintHash
        Set-ObjectProperty -Object $ExistingSource -Name StrongHash -Value $Profile.StrongHash
        Set-ObjectProperty -Object $ExistingSource -Name MediumHash -Value $Profile.MediumHash
        Set-ObjectProperty -Object $ExistingSource -Name WeakHash -Value $Profile.WeakHash
        Set-ObjectProperty -Object $ExistingSource -Name VolumeGuid -Value $Profile.VolumeGuid
        Set-ObjectProperty -Object $ExistingSource -Name VolumeSerial -Value $Profile.VolumeSerial
        Set-ObjectProperty -Object $ExistingSource -Name FileSystem -Value $Profile.FileSystem
        Set-ObjectProperty -Object $ExistingSource -Name TotalSize -Value $Profile.TotalSize
        Set-ObjectProperty -Object $ExistingSource -Name DriveType -Value $Profile.DriveType
        Set-ObjectProperty -Object $ExistingSource -Name BusType -Value $Profile.BusType
        Set-ObjectProperty -Object $ExistingSource -Name StorageDeviceSerial -Value $Profile.StorageDeviceSerial
        Set-ObjectProperty -Object $ExistingSource -Name NativeVendorId -Value $Profile.NativeVendorId
        Set-ObjectProperty -Object $ExistingSource -Name NativeProductId -Value $Profile.NativeProductId
        Set-ObjectProperty -Object $ExistingSource -Name NativeProductRevision -Value $Profile.NativeProductRevision
        Set-ObjectProperty -Object $ExistingSource -Name NativeRemovableMedia -Value $Profile.NativeRemovableMedia
        Set-ObjectProperty -Object $ExistingSource -Name HardwareSerial -Value $Profile.HardwareSerial
        Set-ObjectProperty -Object $ExistingSource -Name HardwarePnpDeviceId -Value $Profile.HardwarePnpDeviceId
        Set-ObjectProperty -Object $ExistingSource -Name HardwareModel -Value $Profile.HardwareModel
        Set-ObjectProperty -Object $ExistingSource -Name HardwareInterface -Value $Profile.HardwareInterface
        Set-ObjectProperty -Object $ExistingSource -Name HardwareMediaType -Value $Profile.HardwareMediaType
        Set-ObjectProperty -Object $ExistingSource -Name LastDosDevicePath -Value $Profile.DosDevicePath
        Set-ObjectProperty -Object $ExistingSource -Name LastVolumeLabel -Value $Profile.VolumeLabel
        Set-ObjectProperty -Object $ExistingSource -Name Components -Value $Profile.Components
        Set-ObjectProperty -Object $ExistingSource -Name LastRoot -Value $Profile.Root
        Set-ObjectProperty -Object $ExistingSource -Name LastSeenAtUtc -Value ([DateTime]::UtcNow.ToString("o"))
        if (-not [string]::IsNullOrWhiteSpace($LegacyDeviceId)) {
            Set-ObjectProperty -Object $ExistingSource -Name LegacyDeviceId -Value $LegacyDeviceId
        }
    }
    else {
        $script:Config.TrustedSources = @(@($script:Config.TrustedSources) + (New-TrustedSourceRecord -Profile $Profile -LegacyDeviceId $LegacyDeviceId))
    }

    Save-Config
}

function Save-IgnoredSource {
    param([Parameter(Mandatory = $true)]$Profile)

    $existing = (Find-IgnoredSource -Profile $Profile).Source
    if ($existing -ne $null) {
        $sourceIdentityHashes = Merge-UniqueTextValues @(
            (Get-ObjectPropertyValue -Object $existing -Name "SourceIdentityHashes"),
            (Get-ObjectPropertyValue -Object $existing -Name "SourceIdentityHash"),
            (Get-ObjectPropertyValue -Object $existing -Name "FingerprintHash"),
            $Profile.SourceIdentityHash
        )

        Set-ObjectProperty -Object $existing -Name Name -Value $Profile.DisplayName
        Set-ObjectProperty -Object $existing -Name SourceIdentityHash -Value $Profile.SourceIdentityHash
        Set-ObjectProperty -Object $existing -Name SourceIdentityHashes -Value @($sourceIdentityHashes)
        Set-ObjectProperty -Object $existing -Name VolumeStateHash -Value $Profile.VolumeStateHash
        Set-ObjectProperty -Object $existing -Name CrossConnectionHash -Value $Profile.CrossConnectionHash
        Set-ObjectProperty -Object $existing -Name FingerprintHash -Value $Profile.FingerprintHash
        Set-ObjectProperty -Object $existing -Name StrongHash -Value $Profile.StrongHash
        Set-ObjectProperty -Object $existing -Name MediumHash -Value $Profile.MediumHash
        Set-ObjectProperty -Object $existing -Name WeakHash -Value $Profile.WeakHash
        Set-ObjectProperty -Object $existing -Name VolumeGuid -Value $Profile.VolumeGuid
        Set-ObjectProperty -Object $existing -Name VolumeSerial -Value $Profile.VolumeSerial
        Set-ObjectProperty -Object $existing -Name FileSystem -Value $Profile.FileSystem
        Set-ObjectProperty -Object $existing -Name TotalSize -Value $Profile.TotalSize
        Set-ObjectProperty -Object $existing -Name DriveType -Value $Profile.DriveType
        Set-ObjectProperty -Object $existing -Name BusType -Value $Profile.BusType
        Set-ObjectProperty -Object $existing -Name StorageDeviceSerial -Value $Profile.StorageDeviceSerial
        Set-ObjectProperty -Object $existing -Name NativeVendorId -Value $Profile.NativeVendorId
        Set-ObjectProperty -Object $existing -Name NativeProductId -Value $Profile.NativeProductId
        Set-ObjectProperty -Object $existing -Name NativeProductRevision -Value $Profile.NativeProductRevision
        Set-ObjectProperty -Object $existing -Name NativeRemovableMedia -Value $Profile.NativeRemovableMedia
        Set-ObjectProperty -Object $existing -Name LastDosDevicePath -Value $Profile.DosDevicePath
        Set-ObjectProperty -Object $existing -Name LastVolumeLabel -Value $Profile.VolumeLabel
        Set-ObjectProperty -Object $existing -Name Components -Value $Profile.Components
        Set-ObjectProperty -Object $existing -Name LastRoot -Value $Profile.Root
        Set-ObjectProperty -Object $existing -Name LastSeenAtUtc -Value ([DateTime]::UtcNow.ToString("o"))
    }
    else {
        $script:Config.IgnoredSources = @(@($script:Config.IgnoredSources) + (New-TrustedSourceRecord -Profile $Profile))
    }

    Save-Config
}

function Test-SameTextValue {
    param(
        $Left,
        $Right
    )

    if ([string]::IsNullOrWhiteSpace([string]$Left) -or [string]::IsNullOrWhiteSpace([string]$Right)) {
        return $false
    }

    return [string]::Equals([string]$Left, [string]$Right, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-SameInt64Value {
    param(
        $Left,
        $Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    try {
        return ([int64]$Left -eq [int64]$Right)
    }
    catch {
        return $false
    }
}

function Test-ProfileLooksCardLike {
    param($Profile)

    $driveType = [string](Get-ObjectPropertyValue -Object $Profile -Name "DriveType")
    if ([string]::Equals($driveType, "Removable", [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $nativeRemovableMedia = Get-ObjectPropertyValue -Object $Profile -Name "NativeRemovableMedia"
    if ($nativeRemovableMedia -ne $null) {
        try {
            if ([bool]$nativeRemovableMedia) {
                return $true
            }
        }
        catch {
        }
    }

    $busType = Get-ObjectPropertyValue -Object $Profile -Name "BusType"
    if ($busType -ne $null) {
        try {
            if (Test-ExternalStorageBusType -BusType ([int]$busType)) {
                return $true
            }
        }
        catch {
        }
    }

    $hardwareText = @(
        (Get-ObjectPropertyValue -Object $Profile -Name "HardwareModel"),
        (Get-ObjectPropertyValue -Object $Profile -Name "HardwareInterface"),
        (Get-ObjectPropertyValue -Object $Profile -Name "HardwareMediaType"),
        (Get-ObjectPropertyValue -Object $Profile -Name "HardwarePnpDeviceId"),
        (Get-ObjectPropertyValue -Object $Profile -Name "NativeVendorId"),
        (Get-ObjectPropertyValue -Object $Profile -Name "NativeProductId")
    ) -join " "

    return ($hardwareText -match '(?i)\b(card|reader|sd|mmc|memory)\b')
}

function Test-StableSourceAutoMatch {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)]$Source
    )

    $profileStorageSerial = Get-ObjectPropertyValue -Object $Profile -Name "StorageDeviceSerial"
    $sourceStorageSerial = Get-ObjectPropertyValue -Object $Source -Name "StorageDeviceSerial"
    $profileVolumeGuid = Get-ObjectPropertyValue -Object $Profile -Name "VolumeGuid"
    $sourceVolumeGuid = Get-ObjectPropertyValue -Object $Source -Name "VolumeGuid"
    $profileVolumeSerial = Get-ObjectPropertyValue -Object $Profile -Name "VolumeSerial"
    $sourceVolumeSerial = Get-ObjectPropertyValue -Object $Source -Name "VolumeSerial"
    $profileTotalSize = Get-ObjectPropertyValue -Object $Profile -Name "TotalSize"
    $sourceTotalSize = Get-ObjectPropertyValue -Object $Source -Name "TotalSize"
    $profileFileSystem = Get-ObjectPropertyValue -Object $Profile -Name "FileSystem"
    $sourceFileSystem = Get-ObjectPropertyValue -Object $Source -Name "FileSystem"
    $profileDriveType = Get-ObjectPropertyValue -Object $Profile -Name "DriveType"
    $sourceDriveType = Get-ObjectPropertyValue -Object $Source -Name "DriveType"

    if ((Test-SameTextValue $profileStorageSerial $sourceStorageSerial) -and (Test-SameTextValue $profileVolumeGuid $sourceVolumeGuid)) {
        return $true
    }

    if ((Test-SameTextValue $profileVolumeGuid $sourceVolumeGuid) -and
        (Test-SameTextValue $profileVolumeSerial $sourceVolumeSerial) -and
        (Test-SameInt64Value $profileTotalSize $sourceTotalSize)) {
        return $true
    }

    $profileLooksCardLike = Test-ProfileLooksCardLike -Profile $Profile
    $sourceLooksCardLike = Test-ProfileLooksCardLike -Profile $Source
    if (-not $profileLooksCardLike -and -not $sourceLooksCardLike -and
        (Test-SameTextValue $profileStorageSerial $sourceStorageSerial) -and
        (Test-SameInt64Value $profileTotalSize $sourceTotalSize) -and
        (Test-SameTextValue $profileFileSystem $sourceFileSystem) -and
        (Test-SameTextValue $profileDriveType $sourceDriveType)) {
        return $true
    }

    return $false
}

function Find-SourceMatch {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)]$Sources
    )

    foreach ($source in @($Sources)) {
        if ($source -eq $null) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.SourceIdentityHash) -and
            (Test-ObjectProperty -Object $source -Name "SourceIdentityHash") -and
            [string]::Equals($source.SourceIdentityHash, $Profile.SourceIdentityHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "Strong"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.SourceIdentityHash) -and
            (Test-ObjectProperty -Object $source -Name "SourceIdentityHashes") -and
            (@(ConvertTo-StringArray $source.SourceIdentityHashes) -contains $Profile.SourceIdentityHash)) {
            return [pscustomobject]@{ MatchType = "Strong"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.FingerprintHash) -and
            (Test-ObjectProperty -Object $source -Name "FingerprintHash") -and
            [string]::Equals($source.FingerprintHash, $Profile.FingerprintHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "Strong"; Source = $source }
        }

        if (Test-StableSourceAutoMatch -Profile $Profile -Source $source) {
            return [pscustomobject]@{ MatchType = "Strong"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.StrongHash) -and
            (Test-ObjectProperty -Object $source -Name "StrongHash") -and
            [string]::Equals($source.StrongHash, $Profile.StrongHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "Partial"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.MediumHash) -and
            (Test-ObjectProperty -Object $source -Name "MediumHash") -and
            [string]::Equals($source.MediumHash, $Profile.MediumHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "Partial"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.CrossConnectionHash) -and
            (Test-ObjectProperty -Object $source -Name "CrossConnectionHash") -and
            [string]::Equals($source.CrossConnectionHash, $Profile.CrossConnectionHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "CrossConnection"; Source = $source }
        }

        if (-not [string]::IsNullOrWhiteSpace($Profile.WeakHash) -and
            (Test-ObjectProperty -Object $source -Name "WeakHash") -and
            [string]::Equals($source.WeakHash, $Profile.WeakHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ MatchType = "Partial"; Source = $source }
        }
    }

    return [pscustomobject]@{ MatchType = "None"; Source = $null }
}

function Find-TrustedSource {
    param([Parameter(Mandatory = $true)]$Profile)
    return (Find-SourceMatch -Profile $Profile -Sources $script:Config.TrustedSources)
}

function Find-IgnoredSource {
    param([Parameter(Mandatory = $true)]$Profile)
    return (Find-SourceMatch -Profile $Profile -Sources $script:Config.IgnoredSources)
}

function Show-SourceTrustDialog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $AppName
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 520, 220
    $form.Font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", 9
    $form.Icon = Get-TrayIcon

    $iconBox = New-Object System.Windows.Forms.PictureBox
    $iconBox.Location = New-Object System.Drawing.Point -ArgumentList 18, 28
    $iconBox.Size = New-Object System.Drawing.Size -ArgumentList 40, 40
    $iconBox.Image = [System.Drawing.SystemIcons]::Question.ToBitmap()
    $form.Controls.Add($iconBox)

    $messageLabel = New-Object System.Windows.Forms.Label
    $messageLabel.Text = $Message
    $messageLabel.Location = New-Object System.Drawing.Point -ArgumentList 72, 18
    $messageLabel.Size = New-Object System.Drawing.Size -ArgumentList 430, 120
    $messageLabel.AutoEllipsis = $true
    $form.Controls.Add($messageLabel)

    $trustButton = New-Object System.Windows.Forms.Button
    $trustButton.Text = T "TrustAndBackup"
    $trustButton.Location = New-Object System.Drawing.Point -ArgumentList 48, 162
    $trustButton.Size = New-Object System.Drawing.Size -ArgumentList 135, 32
    $trustButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Tag = "Trust"; $sender.FindForm().Close() })
    $form.Controls.Add($trustButton)
    $form.AcceptButton = $trustButton

    $skipOnceButton = New-Object System.Windows.Forms.Button
    $skipOnceButton.Text = T "SkipThisTime"
    $skipOnceButton.Location = New-Object System.Drawing.Point -ArgumentList 198, 162
    $skipOnceButton.Size = New-Object System.Drawing.Size -ArgumentList 135, 32
    $skipOnceButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Tag = "SkipOnce"; $sender.FindForm().Close() })
    $form.Controls.Add($skipOnceButton)

    $alwaysSkipButton = New-Object System.Windows.Forms.Button
    $alwaysSkipButton.Text = T "AlwaysSkip"
    $alwaysSkipButton.Location = New-Object System.Drawing.Point -ArgumentList 348, 162
    $alwaysSkipButton.Size = New-Object System.Drawing.Size -ArgumentList 135, 32
    $alwaysSkipButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Tag = "SkipAlways"; $sender.FindForm().Close() })
    $form.Controls.Add($alwaysSkipButton)
    $form.CancelButton = $skipOnceButton

    [void]$form.ShowDialog()
    $decision = [string]$form.Tag
    $form.Dispose()
    if ([string]::IsNullOrWhiteSpace($decision)) {
        return "SkipOnce"
    }

    return $decision
}

function Request-SourceTrust {
    param(
        [Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive,
        [Parameter(Mandatory = $true)]$Profile,
        $Match = $null
    )

    $root = $Drive.RootDirectory.FullName
    if ($script:IgnoredRoots.ContainsKey($root)) {
        return $false
    }

    $label = if ([string]::IsNullOrWhiteSpace($Drive.VolumeLabel)) { T "NoLabel" } else { $Drive.VolumeLabel }
    $matchedName = $null
    if ($Match -ne $null -and $Match.Source -ne $null -and (Test-ObjectProperty -Object $Match.Source -Name "Name")) {
        $matchedName = Get-ObjectPropertyValue -Object $Match.Source -Name "Name"
    }
    $message = if ($Match -ne $null -and $Match.MatchType -eq "CrossConnection") {
        T "CrossConnectionTrustMessage" @($root, $label, $matchedName)
    }
    elseif ($Match -ne $null -and $Match.MatchType -eq "Partial") {
        T "PossibleTrustMessage" @($root, $label, $matchedName)
    }
    else {
        T "TrustMessage" @($root, $label)
    }
    $result = Show-SourceTrustDialog -Message $message

    if ($result -eq "SkipAlways") {
        Save-IgnoredSource -Profile $Profile
        $script:IgnoredRoots[$root] = $true
        Write-Log -Message "User added '$root' to skipped sources"
        Show-Notice -Title $AppName -Text (T "SkippedSourceSaved")
        return $false
    }

    if ($result -ne "Trust") {
        $script:IgnoredRoots[$root] = $true
        Write-Log -Message "User declined trust for '$root'"
        return $false
    }

    $existing = if ($Match -ne $null) { $Match.Source } else { $null }
    Save-TrustedSource -Profile $Profile -ExistingSource $existing
    Write-Log -Message "Trusted source '$($Profile.SourceIdentityHash)' at '$root'"
    $trustedNoticeKey = if ([string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup") { "TrustedNoticeConfirmMode" } else { "TrustedNotice" }
    Show-Notice -Title $AppName -Text (T $trustedNoticeKey @($root))
    return $true
}

function Resolve-SourceTrust {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $profile = New-SourceProfile -Drive $Drive
    $ignoredMatch = Find-IgnoredSource -Profile $profile
    if ($ignoredMatch.MatchType -ne "None") {
        Write-Log -Message "Skipped ignored source '$($profile.SourceIdentityHash)' at '$($Drive.RootDirectory.FullName)'. MatchType=$($ignoredMatch.MatchType)"
        return $false
    }

    $marker = Read-DeviceMarker -Drive $Drive
    if ($marker -ne $null -and -not [string]::IsNullOrWhiteSpace($marker.DeviceId) -and (Test-TrustedDevice -DeviceId $marker.DeviceId)) {
        Save-TrustedSource -Profile $profile -LegacyDeviceId $marker.DeviceId
        Write-Log -Message "Trusted source by legacy marker '$($marker.DeviceId)' at '$($Drive.RootDirectory.FullName)'"
        return $true
    }

    $match = Find-TrustedSource -Profile $profile
    if ($match.MatchType -eq "Strong") {
        Save-TrustedSource -Profile $profile -ExistingSource $match.Source
        return $true
    }

    return (Request-SourceTrust -Drive $Drive -Profile $profile -Match $match)
}

function Confirm-BackupStart {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $root = $Drive.RootDirectory.FullName
    $label = if ([string]::IsNullOrWhiteSpace($Drive.VolumeLabel)) { T "NoLabel" } else { $Drive.VolumeLabel }
    $result = [System.Windows.Forms.MessageBox]::Show(
        (T "ConfirmBackupStart" @($root, $label)),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log -Message "User skipped backup for '$root' until reinsertion"
        return $false
    }

    return $true
}

function Get-MediaFiles {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $root = $Drive.RootDirectory.FullName
    $excludedFolders = @($script:Config.ExcludedFolders | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    try {
        return Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                if ($script:SupportedExtensions -notcontains $_.Extension.ToLowerInvariant()) {
                    return $false
                }
                if ($_.FullName -like "*\$MarkerFileName") {
                    return $false
                }
                if ($script:Config.MinFileSizeBytes -gt 0 -and $_.Length -lt $script:Config.MinFileSizeBytes) {
                    return $false
                }
                foreach ($folderName in $excludedFolders) {
                    if ($_.FullName -like "*\$folderName\*") {
                        return $false
                    }
                }
                return $true
            }
    }
    catch {
        Write-Log -Level "ERROR" -Message "Failed to scan '$root': $($_.Exception.Message)"
        return @()
    }
}

function Get-MediaCategory {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$SourceFile)

    $extension = $SourceFile.Extension.ToLowerInvariant()
    if ($RawExtensions -contains $extension) {
        return "RAW"
    }
    if ($VideoExtensions -contains $extension) {
        return "Videos"
    }
    return "Photos"
}

function ConvertTo-SafeFolderName {
    param(
        [string]$Name,
        [string]$Fallback = "Unknown device",
        [int]$MaxLength = 80
    )

    $value = ([string]$Name).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Fallback
    }

    foreach ($invalidChar in [System.IO.Path]::GetInvalidFileNameChars()) {
        $value = $value.Replace([string]$invalidChar, "_")
    }
    $value = ($value -replace '\s+', ' ').Trim().Trim(".")
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Fallback
    }
    if ($value.Length -gt $MaxLength) {
        $value = $value.Substring(0, $MaxLength).Trim().Trim(".")
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Fallback
    }

    return $value
}

function Get-SourceDisplayFolderBaseName {
    param($Source)

    $name = Get-ObjectPropertyValue -Object $Source -Name "DisplayName"
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-ObjectPropertyValue -Object $Source -Name "Name"
    }
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-ObjectPropertyValue -Object $Source -Name "VolumeLabel"
    }
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-ObjectPropertyValue -Object $Source -Name "LastVolumeLabel"
    }
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-ObjectPropertyValue -Object $Source -Name "Root"
    }
    if ([string]::IsNullOrWhiteSpace([string]$name)) {
        $name = Get-ObjectPropertyValue -Object $Source -Name "LastRoot"
    }

    return (ConvertTo-SafeFolderName -Name ([string]$name) -Fallback (T "UnknownDeviceFolder"))
}

function Get-SourceShortHash {
    param($Source)

    $hash = Get-ObjectPropertyValue -Object $Source -Name "SourceIdentityHash"
    if ([string]::IsNullOrWhiteSpace([string]$hash)) {
        $hash = Get-ObjectPropertyValue -Object $Source -Name "FingerprintHash"
    }
    if ([string]::IsNullOrWhiteSpace([string]$hash)) {
        $hash = Get-ObjectPropertyValue -Object $Source -Name "CrossConnectionHash"
    }
    if ([string]::IsNullOrWhiteSpace([string]$hash)) {
        $hash = Get-ObjectPropertyValue -Object $Source -Name "VolumeStateHash"
    }
    if ([string]::IsNullOrWhiteSpace([string]$hash)) {
        return "SOURCE"
    }

    $hashText = ([string]$hash).ToUpperInvariant()
    if ($hashText.Length -gt 6) {
        return $hashText.Substring(0, 6)
    }
    return $hashText
}

function Test-SourceRecordMatchesProfile {
    param(
        $Source,
        $Profile
    )

    $profileIdentityHash = Get-ObjectPropertyValue -Object $Profile -Name "SourceIdentityHash"
    $sourceIdentityHashes = Merge-UniqueTextValues @(
        (Get-ObjectPropertyValue -Object $Source -Name "SourceIdentityHashes"),
        (Get-ObjectPropertyValue -Object $Source -Name "SourceIdentityHash"),
        (Get-ObjectPropertyValue -Object $Source -Name "FingerprintHash")
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$profileIdentityHash) -and @($sourceIdentityHashes) -contains $profileIdentityHash) {
        return $true
    }

    $profileCrossHash = Get-ObjectPropertyValue -Object $Profile -Name "CrossConnectionHash"
    $sourceCrossHash = Get-ObjectPropertyValue -Object $Source -Name "CrossConnectionHash"
    return (Test-SameTextValue $profileCrossHash $sourceCrossHash)
}

function Get-DeviceBackupFolderName {
    param($Profile)

    $baseName = Get-SourceDisplayFolderBaseName -Source $Profile
    $sameNameSources = @(
        foreach ($source in @($script:Config.TrustedSources)) {
            if ([string]::Equals((Get-SourceDisplayFolderBaseName -Source $source), $baseName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $source
            }
        }
    )

    if ($sameNameSources.Count -le 1) {
        return $baseName
    }

    $matchingSource = $null
    foreach ($source in $sameNameSources) {
        if (Test-SourceRecordMatchesProfile -Source $source -Profile $Profile) {
            $matchingSource = $source
            break
        }
    }

    if ($matchingSource -ne $null -and [object]::ReferenceEquals($matchingSource, $sameNameSources[0])) {
        return $baseName
    }

    $shortHash = Get-SourceShortHash -Source $Profile
    $trimmedBase = ConvertTo-SafeFolderName -Name $baseName -Fallback (T "UnknownDeviceFolder") -MaxLength 72
    return (ConvertTo-SafeFolderName -Name ("{0}-{1}" -f $trimmedBase, $shortHash) -Fallback (T "UnknownDeviceFolder"))
}

function Get-DestinationPath {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [string]$DeviceFolderName
    )

    $date = $SourceFile.LastWriteTime
    $baseFolder = $script:Config.BackupRoot
    if ([bool]$script:Config.GroupBySourceDevice -and -not [string]::IsNullOrWhiteSpace($DeviceFolderName)) {
        $baseFolder = Join-Path $baseFolder (ConvertTo-SafeFolderName -Name $DeviceFolderName -Fallback (T "UnknownDeviceFolder"))
    }
    if ([bool]$script:Config.SplitByMediaType) {
        $baseFolder = Join-Path $baseFolder (Get-MediaCategory -SourceFile $SourceFile)
    }

    $dateFolder = Join-Path (Join-Path $baseFolder ($date.ToString("yyyy"))) ($date.ToString("yyyy-MM-dd"))
    if ([bool]$script:Config.PreserveSourceStructure) {
        $relativeParent = ""
        try {
            $sourceRootFull = [System.IO.Path]::GetFullPath($SourceRoot)
            $sourceParent = [System.IO.Path]::GetDirectoryName($SourceFile.FullName)
            if ($sourceParent.Length -gt $sourceRootFull.Length) {
                $relativeParent = $sourceParent.Substring($sourceRootFull.Length).TrimStart("\")
            }
        }
        catch {
            $relativeParent = ""
        }
        if (-not [string]::IsNullOrWhiteSpace($relativeParent)) {
            $dateFolder = Join-Path $dateFolder $relativeParent
        }
    }
    Ensure-Directory -Path $dateFolder

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
    $extension = $SourceFile.Extension
    $candidate = Join-Path $dateFolder $SourceFile.Name
    $index = 1

    while ([System.IO.File]::Exists($candidate)) {
        $candidateName = "{0} ({1}){2}" -f $baseName, $index, $extension
        $candidate = Join-Path $dateFolder $candidateName
        $index++
    }

    return $candidate
}

function Test-ManifestBackupEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Hash,
        $Entry = $null
    )

    $backupPath = Get-ObjectPropertyValue -Object $Entry -Name "BackupPath"
    if ([string]::IsNullOrWhiteSpace($backupPath) -or -not [System.IO.File]::Exists($backupPath)) {
        return $false
    }

    $recordedSize = Get-ObjectPropertyValue -Object $Entry -Name "Size"
    if ($recordedSize -ne $null) {
        try {
            $backupInfo = Get-Item -LiteralPath $backupPath -ErrorAction Stop
            if ([int64]$recordedSize -ne [int64]$backupInfo.Length) {
                return $false
            }
        }
        catch {
            return $false
        }
    }

    try {
        $backupHash = Get-FileSha256Hash -Path $backupPath
        return [string]::Equals($backupHash, $Hash, [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to verify manifest backup path '$backupPath': $($_.Exception.Message)"
        return $false
    }
}

function Invoke-UiPump {
    try {
        [System.Windows.Forms.Application]::DoEvents()
    }
    catch {
        # Best-effort only. Backup integrity must not depend on UI message pumping.
    }
}

function Get-FileSha256Hash {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $buffer = New-Object byte[] (1024 * 1024 * 4)
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            Invoke-UiPump
        }
        [void]$sha.TransformFinalBlock($buffer, 0, 0)
        return (($sha.Hash | ForEach-Object { $_.ToString("x2") }) -join "").ToUpperInvariant()
    }
    finally {
        if ($stream -ne $null) {
            $stream.Dispose()
        }
        $sha.Dispose()
    }
}

function Copy-FileWithUiPump {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $sourceStream = $null
    $destinationStream = $null
    try {
        $sourceStream = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $destinationStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = New-Object byte[] (1024 * 1024 * 4)
        while (($read = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $destinationStream.Write($buffer, 0, $read)
            Invoke-UiPump
        }
        $destinationStream.Flush()
    }
    finally {
        if ($destinationStream -ne $null) {
            $destinationStream.Dispose()
        }
        if ($sourceStream -ne $null) {
            $sourceStream.Dispose()
        }
    }
}

function Copy-MediaFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$SourceFile,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [string]$DeviceFolderName
    )

    $destination = $null
    try {
        $sourceHash = Get-FileSha256Hash -Path $SourceFile.FullName
        if ($script:Manifest.Hashes.ContainsKey($sourceHash)) {
            $existing = $script:Manifest.Hashes[$sourceHash]
            $backupPath = Get-ObjectPropertyValue -Object $existing -Name "BackupPath"
            if (Test-ManifestBackupEntry -Hash $sourceHash -Entry $existing) {
                $backupFolder = if (-not [string]::IsNullOrWhiteSpace($backupPath)) { Split-Path -Parent $backupPath } else { $null }
                return [pscustomobject]@{ Status = "Skipped"; Path = $SourceFile.FullName; Destination = $backupPath; DestinationFolder = $backupFolder; Bytes = $SourceFile.Length; Error = $null }
            }

            [void]$script:Manifest.Hashes.Remove($sourceHash)
            Write-Log -Level "WARN" -Message "Manifest entry for '$($SourceFile.FullName)' was stale; file will be copied again."
        }

        $destination = Get-DestinationPath -SourceFile $SourceFile -SourceRoot $SourceRoot -DeviceFolderName $DeviceFolderName
        Copy-FileWithUiPump -SourcePath $SourceFile.FullName -DestinationPath $destination

        $destinationInfo = Get-Item -LiteralPath $destination
        if ($destinationInfo.Length -ne $SourceFile.Length) {
            throw "Size mismatch after copy. Source=$($SourceFile.Length), Destination=$($destinationInfo.Length)"
        }

        $destinationHash = Get-FileSha256Hash -Path $destination
        if ($destinationHash -ne $sourceHash) {
            throw "Hash mismatch after copy."
        }

        $script:Manifest.Hashes[$sourceHash] = [pscustomobject]@{
            SourcePath = $SourceFile.FullName
            BackupPath = $destination
            Size = $SourceFile.Length
            LastWriteTimeUtc = $SourceFile.LastWriteTimeUtc.ToString("o")
            BackedUpAtUtc = [DateTime]::UtcNow.ToString("o")
        }

        return [pscustomobject]@{ Status = "Copied"; Path = $SourceFile.FullName; Destination = $destination; DestinationFolder = (Split-Path -Parent $destination); Bytes = $SourceFile.Length; Error = $null }
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($destination) -and [System.IO.File]::Exists($destination)) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
        Write-Log -Level "ERROR" -Message "Failed to back up '$($SourceFile.FullName)': $($_.Exception.Message)"
        return [pscustomobject]@{ Status = "Failed"; Path = $SourceFile.FullName; Destination = $null; DestinationFolder = $null; Bytes = $SourceFile.Length; Error = $_.Exception.Message }
    }
}

function Backup-Drive {
    param([Parameter(Mandatory = $true)][System.IO.DriveInfo]$Drive)

    $root = $Drive.RootDirectory.FullName
    $startedAt = Get-Date
    $deviceFolderName = $null
    if ([bool]$script:Config.GroupBySourceDevice) {
        try {
            $sourceProfile = New-SourceProfile -Drive $Drive
            $deviceFolderName = Get-DeviceBackupFolderName -Profile $sourceProfile
        }
        catch {
            Write-Log -Level "WARN" -Message "Failed to resolve device backup folder name for '$root': $($_.Exception.Message)"
            $deviceFolderName = ConvertTo-SafeFolderName -Name $Drive.VolumeLabel -Fallback (T "UnknownDeviceFolder")
        }
    }
    Write-Log -Message "Scanning '$root'"

    $files = @(Get-MediaFiles -Drive $Drive)
    if ($files.Count -eq 0) {
        Write-Log -Message "No media files found on '$root'"
        $emptyResult = [pscustomobject]@{
            StartedAtLocal = $startedAt.ToString("yyyy-MM-dd HH:mm:ss")
            FinishedAtLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Source = $root
            Copied = 0
            Skipped = 0
            Failed = 0
            Total = 0
            BackupFolder = $null
            DestinationFolders = @()
            Status = "NoMedia"
            LastError = $null
        }
        Save-LastBackupResult -Result $emptyResult
        return $emptyResult
    }

    Show-Notice -Title $AppName -Text (T "BackingUpNotice" @($files.Count, $root))
    $copied = 0
    $skipped = 0
    $failed = 0
    $processed = 0
    $destinationFolders = @()
    $lastError = $null

    foreach ($file in $files) {
        $processed++
        if ($script:NotifyIcon -ne $null) {
            $script:NotifyIcon.Text = ("{0}: {1}/{2}" -f $AppName, $processed, $files.Count)
        }

        $result = Copy-MediaFile -SourceFile $file -SourceRoot $root -DeviceFolderName $deviceFolderName
        switch ($result.Status) {
            "Copied" { $copied++ }
            "Skipped" { $skipped++ }
            default {
                $failed++
                if ([string]::IsNullOrWhiteSpace($lastError) -and -not [string]::IsNullOrWhiteSpace($result.Error)) {
                    $lastError = $result.Error
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($result.DestinationFolder)) {
            $destinationFolders += $result.DestinationFolder
        }

        if (($processed % 10) -eq 0) {
            Save-Manifest
        }
    }

    Save-Manifest
    Write-Log -Message "Finished '$root': copied=$copied skipped=$skipped failed=$failed total=$($files.Count)"
    $uniqueDestinationFolders = @($destinationFolders | Select-Object -Unique)
    $recentFolder = if ($uniqueDestinationFolders.Count -gt 0) { $uniqueDestinationFolders[-1] } else { $null }
    $status = if ($failed -gt 0) { "Failed" } elseif ($copied -eq 0 -and $skipped -gt 0) { "Skipped" } else { "Completed" }
    $resultSummary = [pscustomobject]@{
        StartedAtLocal = $startedAt.ToString("yyyy-MM-dd HH:mm:ss")
        FinishedAtLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Source = $root
        Copied = $copied
        Skipped = $skipped
        Failed = $failed
        Total = $files.Count
        BackupFolder = $recentFolder
        DestinationFolders = @($uniqueDestinationFolders)
        Status = $status
        LastError = $lastError
    }
    Save-LastBackupResult -Result $resultSummary
    return $resultSummary
}

function Invoke-ScanAll {
    param([switch]$Force)

    if ($script:IsScanning) {
        return
    }

    $script:IsScanning = $true
    try {
        if (-not $Force -and -not $script:Config.AutoBackupEnabled) {
            $drives = @(Get-CandidateDrives)
            $seenRoots = @{}
            foreach ($drive in $drives) {
                $root = $drive.RootDirectory.FullName
                $seenRoots[$root] = $true
                $script:CurrentRoots[$root] = $true
            }

            foreach ($root in @($script:IgnoredRoots.Keys)) {
                if (-not $seenRoots.ContainsKey($root)) {
                    $script:IgnoredRoots.Remove($root)
                }
            }

            foreach ($root in @($script:CurrentRoots.Keys)) {
                if (-not $seenRoots.ContainsKey($root)) {
                    $script:CurrentRoots.Remove($root)
                }
            }
            return
        }

        $drives = @(Get-CandidateDrives)
        $seenRoots = @{}
        foreach ($drive in $drives) {
            $root = $drive.RootDirectory.FullName
            $isNewlySeen = -not $script:CurrentRoots.ContainsKey($root)
            $seenRoots[$root] = $true
            $script:CurrentRoots[$root] = $true

            if (-not $Force -and -not $isNewlySeen) {
                continue
            }

            $trusted = Resolve-SourceTrust -Drive $drive

            if ($trusted) {
                if (-not $Force -and [string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup" -and -not (Confirm-BackupStart -Drive $drive)) {
                    continue
                }

                if (-not (Resolve-BackupRootForBackup -Drive $drive)) {
                    continue
                }

                $summary = Backup-Drive -Drive $drive
                if ($script:Config.ShowBackupSummary -and $summary.Total -gt 0) {
                    $text = if (-not [string]::IsNullOrWhiteSpace($summary.BackupFolder)) {
                        T "BackupSummaryWithFolder" @($summary.Copied, $summary.Skipped, $summary.Failed, $root, $summary.BackupFolder)
                    }
                    else {
                        T "BackupSummary" @($summary.Copied, $summary.Skipped, $summary.Failed, $root)
                    }
                    Show-Notice -Title $AppName -Text $text -Icon ([System.Windows.Forms.ToolTipIcon]::Info)
                }
                elseif ($Force -and $script:Config.ShowBackupSummary -and $summary.Total -eq 0) {
                    Show-Notice -Title $AppName -Text (T "NoMediaNotice" @($root)) -Icon ([System.Windows.Forms.ToolTipIcon]::Info)
                }
                if ([bool]$script:Config.OpenFolderAfterBackup -and -not [string]::IsNullOrWhiteSpace($summary.BackupFolder) -and [System.IO.Directory]::Exists($summary.BackupFolder)) {
                    Start-Process -FilePath $summary.BackupFolder
                }
            }
        }

        foreach ($root in @($script:IgnoredRoots.Keys)) {
            if (-not $seenRoots.ContainsKey($root)) {
                $script:IgnoredRoots.Remove($root)
            }
        }

        foreach ($root in @($script:CurrentRoots.Keys)) {
            if (-not $seenRoots.ContainsKey($root)) {
                $script:CurrentRoots.Remove($root)
            }
        }
    }
    catch {
        Write-Log -Level "ERROR" -Message "Scan failed: $($_.Exception.Message)"
        Show-Notice -Title $AppName -Text (T "ScanFailedNotice") -Icon ([System.Windows.Forms.ToolTipIcon]::Error)
    }
    finally {
        if ($script:NotifyIcon -ne $null) {
            $script:NotifyIcon.Text = $AppName
        }
        $script:IsScanning = $false
    }
}

function Open-BackupRoot {
    if (Ensure-BackupRoot) {
        Start-Process -FilePath $script:Config.BackupRoot
    }
}

function Open-Log {
    Ensure-Directory -Path $LogDir
    if (-not [System.IO.File]::Exists($LogPath)) {
        Set-Content -LiteralPath $LogPath -Value "" -Encoding UTF8
    }
    Start-Process -FilePath "notepad.exe" -ArgumentList "`"$LogPath`""
}

function Open-LogFolder {
    Ensure-Directory -Path $LogDir
    Start-Process -FilePath $LogDir
}

function Get-StartupShortcutPaths {
    $startupDir = [Environment]::GetFolderPath("Startup")
    return @(
        (Join-Path $startupDir "Plug & Backup.lnk"),
        (Join-Path $startupDir "随插备份.lnk"),
        (Join-Path $startupDir "USB Photo Backup.lnk"),
        (Join-Path $startupDir "USB 照片视频备份.lnk")
    )
}

function Get-PrimaryStartupShortcutPath {
    $startupDir = [Environment]::GetFolderPath("Startup")
    return (Join-Path $startupDir "$AppName.lnk")
}

function Test-StartupShortcutEnabled {
    foreach ($shortcutPath in (Get-StartupShortcutPaths)) {
        if ([System.IO.File]::Exists($shortcutPath)) {
            return $true
        }
    }
    return $false
}

function Enable-StartupShortcut {
    $shortcutPath = Get-PrimaryStartupShortcutPath
    $powerShellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)

    if ($script:IsPackagedExe) {
        $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([string]::IsNullOrWhiteSpace($exePath) -or -not [System.IO.File]::Exists($exePath)) {
            throw "Packaged executable was not found."
        }

        $shortcut.TargetPath = $exePath
        $shortcut.Arguments = "-StartMinimized"
        $shortcut.WorkingDirectory = $script:AppRoot
        if ([System.IO.File]::Exists($IconPath)) {
            $shortcut.IconLocation = $IconPath
        }
        else {
            $shortcut.IconLocation = "$exePath,0"
        }
    }
    else {
        $scriptPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { Join-Path $script:AppRoot "UsbPhotoBackup.ps1" }
        if (-not [System.IO.File]::Exists($scriptPath)) {
            throw "UsbPhotoBackup.ps1 was not found."
        }

        $shortcut.TargetPath = $powerShellPath
        $shortcut.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -StartMinimized"
        $shortcut.WorkingDirectory = $script:AppRoot
        if ([System.IO.File]::Exists($IconPath)) {
            $shortcut.IconLocation = $IconPath
        }
        else {
            $shortcut.IconLocation = "$powerShellPath,0"
        }
    }
    $shortcut.Description = $AppName
    $shortcut.Save()
}

function Disable-StartupShortcut {
    foreach ($shortcutPath in (Get-StartupShortcutPaths)) {
        Remove-PathIfExists -Path $shortcutPath
    }
}

function Set-StartupShortcutEnabled {
    param([bool]$Enabled)

    if ($Enabled) {
        Enable-StartupShortcut
    }
    else {
        Disable-StartupShortcut
    }
}

function Remove-PathIfExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if ([System.IO.File]::Exists($Path) -or [System.IO.Directory]::Exists($Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}

function Confirm-Cleanup {
    $firstResult = [System.Windows.Forms.MessageBox]::Show(
        (T "CleanupConfirm"),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($firstResult -ne [System.Windows.Forms.DialogResult]::Yes) {
        return $false
    }

    $secondResult = [System.Windows.Forms.MessageBox]::Show(
        (T "CleanupSecondConfirm"),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    return ($secondResult -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Invoke-Cleanup {
    param([switch]$ExitAfterCleanup)

    if (-not (Confirm-Cleanup)) {
        return $false
    }

    try {
        $script:IsScanning = $true
        if ($script:ScanTimer -ne $null) {
            $script:ScanTimer.Stop()
        }

        foreach ($shortcutPath in (Get-StartupShortcutPaths)) {
            Remove-PathIfExists -Path $shortcutPath
        }

        Remove-PathIfExists -Path $ConfigDir
        Remove-PathIfExists -Path $StateDir

        [System.Windows.Forms.MessageBox]::Show(
            (T "CleanupComplete"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null

        if ($ExitAfterCleanup) {
            if ($script:NotifyIcon -ne $null) {
                $script:NotifyIcon.Visible = $false
                $script:NotifyIcon.Dispose()
                $script:NotifyIcon = $null
            }
            [System.Windows.Forms.Application]::Exit()
        }

        return $true
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            (T "CleanupFailed" @($_.Exception.Message)),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $false
    }
    finally {
        $script:IsScanning = $false
    }
}

function Edit-SupportedExtensions {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "EditExtensions"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 620, 420
    $form.Icon = Get-TrayIcon
    $form.Font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", 9

    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Text = T "EditExtensionsPrompt"
    $promptLabel.Location = New-Object System.Drawing.Point -ArgumentList 16, 16
    $promptLabel.Size = New-Object System.Drawing.Size -ArgumentList 588, 40
    $form.Controls.Add($promptLabel)

    $exampleLabel = New-Object System.Windows.Forms.Label
    $exampleLabel.Text = T "EditExtensionsExample"
    $exampleLabel.Location = New-Object System.Drawing.Point -ArgumentList 16, 58
    $exampleLabel.Size = New-Object System.Drawing.Size -ArgumentList 588, 22
    $form.Controls.Add($exampleLabel)

    $extensionsText = New-Object System.Windows.Forms.TextBox
    $extensionsText.Location = New-Object System.Drawing.Point -ArgumentList 16, 88
    $extensionsText.Size = New-Object System.Drawing.Size -ArgumentList 588, 260
    $extensionsText.Multiline = $true
    $extensionsText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $extensionsText.AcceptsReturn = $true
    $extensionsText.AcceptsTab = $false
    $extensionsText.WordWrap = $true
    $extensionsText.Text = (@($script:SupportedExtensions) | Sort-Object) -join [Environment]::NewLine
    $form.Controls.Add($extensionsText)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = T "Save"
    $saveButton.Location = New-Object System.Drawing.Point -ArgumentList 398, 368
    $saveButton.Size = New-Object System.Drawing.Size -ArgumentList 96, 30
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($saveButton)
    $form.AcceptButton = $saveButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = T "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 508, 368
    $cancelButton.Size = New-Object System.Drawing.Size -ArgumentList 96, 30
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return
    }

    $inputText = $extensionsText.Text
    $form.Dispose()

    if ([string]::IsNullOrWhiteSpace($inputText)) {
        return
    }

    $extensions = @(Normalize-Extensions -Extensions @($inputText))
    if ($extensions.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "ExtensionsInvalid"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $script:Config.FileExtensions = @($extensions)
    $script:SupportedExtensions = @($extensions)
    Save-Config
    Show-Notice -Title $AppName -Text (T "ExtensionsUpdated")
}

function Get-TrayIcon {
    try {
        if ([System.IO.File]::Exists($IconPath)) {
            return (New-Object System.Drawing.Icon $IconPath)
        }

        if ($script:IsPackagedExe) {
            $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            if (-not [string]::IsNullOrWhiteSpace($exePath) -and [System.IO.File]::Exists($exePath)) {
                $exeIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
                if ($exeIcon -ne $null) {
                    return $exeIcon
                }
            }
        }
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to load tray icon '$IconPath': $($_.Exception.Message)"
    }

    return [System.Drawing.SystemIcons]::Information
}

function Get-AutoBackupMenuText {
    if ($script:Config.AutoBackupEnabled) {
        return (T "PauseAutoBackup")
    }

    return (T "ResumeAutoBackup")
}

function Toggle-AutoBackup {
    param($MenuItem)

    $script:Config.AutoBackupEnabled = -not [bool]$script:Config.AutoBackupEnabled
    Save-Config
    if ($MenuItem -ne $null) {
        $MenuItem.Text = Get-AutoBackupMenuText
    }

    $notice = if ($script:Config.AutoBackupEnabled) { T "AutoBackupResumed" } else { T "AutoBackupPaused" }
    Show-Notice -Title $AppName -Text $notice
}

function Get-BackupStartModeMenuText {
    if ([string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup") {
        return (T "BackupModeConfirmBeforeBackup")
    }

    return (T "BackupModeAutomatic")
}

function Toggle-BackupStartMode {
    param($MenuItem)

    if ([string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup") {
        $script:Config.BackupStartMode = "Automatic"
    }
    else {
        $script:Config.BackupStartMode = "ConfirmBeforeBackup"
    }

    Save-Config
    if ($MenuItem -ne $null) {
        $MenuItem.Text = Get-BackupStartModeMenuText
    }

    $notice = if ([string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup") { T "BackupModeSetConfirmBeforeBackup" } else { T "BackupModeSetAutomatic" }
    Show-Notice -Title $AppName -Text $notice
}

function Toggle-BackupSummary {
    param($MenuItem)

    if ($MenuItem -ne $null) {
        $script:Config.ShowBackupSummary = [bool]$MenuItem.Checked
    }
    else {
        $script:Config.ShowBackupSummary = -not [bool]$script:Config.ShowBackupSummary
    }

    Save-Config
}

function Format-TrustedSourceLine {
    param(
        [string]$Index,
        $Source
    )

    $sourceName = Get-ObjectPropertyValue -Object $Source -Name "Name"
    $sourceRoot = Get-ObjectPropertyValue -Object $Source -Name "LastRoot" -DefaultValue ""
    $sourceSeen = Get-ObjectPropertyValue -Object $Source -Name "LastSeenAtUtc" -DefaultValue ""
    $name = if (-not [string]::IsNullOrWhiteSpace($sourceName)) { $sourceName } else { "(unnamed)" }
    $root = if (-not [string]::IsNullOrWhiteSpace($sourceRoot)) { $sourceRoot } else { "" }
    $seen = if (-not [string]::IsNullOrWhiteSpace($sourceSeen)) { $sourceSeen } else { "" }

    return ("{0}. {1} {2} {3}" -f $Index, $name, $root, $seen).Trim()
}

function Manage-TrustedSources {
    $trustedSources = @($script:Config.TrustedSources)
    $ignoredSources = @($script:Config.IgnoredSources)
    if ($trustedSources.Count -eq 0 -and $ignoredSources.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "NoTrustedSources"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $lines = @()
    if ($trustedSources.Count -gt 0) {
        $lines += "[$(T "TrustedSourcesHeader")]"
        for ($i = 0; $i -lt $trustedSources.Count; $i++) {
            $lines += (Format-TrustedSourceLine -Index ("T{0}" -f ($i + 1)) -Source $trustedSources[$i])
        }
        $lines += ""
    }
    if ($ignoredSources.Count -gt 0) {
        $lines += "[$(T "IgnoredSourcesHeader")]"
        for ($i = 0; $i -lt $ignoredSources.Count; $i++) {
            $lines += (Format-TrustedSourceLine -Index ("S{0}" -f ($i + 1)) -Source $ignoredSources[$i])
        }
    }

    $choice = [Microsoft.VisualBasic.Interaction]::InputBox(
        (T "TrustedSourcesPrompt" @(($lines -join "`r`n"))),
        $AppName,
        ""
    )

    if ([string]::IsNullOrWhiteSpace($choice)) {
        return
    }

    $normalizedChoice = $choice.Trim().ToUpperInvariant()
    if ($normalizedChoice -notmatch '^(T|S)(\d+)$') {
        [System.Windows.Forms.MessageBox]::Show(
            (T "InvalidTrustedSourceChoice"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $listKind = $Matches[1]
    $number = [int]$Matches[2]
    $selectedSources = if ($listKind -eq "T") { $trustedSources } else { $ignoredSources }
    if ($number -lt 1 -or $number -gt $selectedSources.Count) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "InvalidTrustedSourceChoice"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    $selected = $selectedSources[$number - 1]
    $selectedLine = Format-TrustedSourceLine -Index $normalizedChoice -Source $selected
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        (T "RemoveTrustedSourceConfirm" @($selectedLine)),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    $remaining = @()
    for ($i = 0; $i -lt $selectedSources.Count; $i++) {
        if ($i -ne ($number - 1)) {
            $remaining += $selectedSources[$i]
        }
    }

    if ($listKind -eq "T") {
        $script:Config.TrustedSources = @($remaining)
    }
    else {
        $script:Config.IgnoredSources = @($remaining)
    }
    Save-Config
    Show-Notice -Title $AppName -Text (T "TrustedSourceRemoved")
}

function Open-ConfigFolder {
    Ensure-Directory -Path $ConfigDir
    Start-Process -FilePath $ConfigDir
}

function Get-LocalizedBackupStatus {
    param([string]$Status)

    switch ($Status) {
        "Completed" { return (T "StatusCompleted") }
        "NoMedia" { return (T "StatusNoMedia") }
        "Skipped" { return (T "StatusSkipped") }
        "Failed" { return (T "StatusFailed") }
        default { return $Status }
    }
}

function Open-RecentBackupFolder {
    $result = $script:LastBackupResult
    if ($result -eq $null) {
        Load-LastBackupResult
        $result = $script:LastBackupResult
    }

    $folder = Get-ObjectPropertyValue -Object $result -Name "BackupFolder"
    if (-not [string]::IsNullOrWhiteSpace($folder) -and [System.IO.Directory]::Exists($folder)) {
        Start-Process -FilePath $folder
        return
    }

    [System.Windows.Forms.MessageBox]::Show(
        (T "NoRecentBackupFolder"),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-LastBackupResult {
    $result = $script:LastBackupResult
    if ($result -eq $null) {
        Load-LastBackupResult
        $result = $script:LastBackupResult
    }

    if ($result -eq $null) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "NoBackupHistory"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    $backupFolder = Get-ObjectPropertyValue -Object $result -Name "BackupFolder" -DefaultValue ""
    $statusValue = Get-ObjectPropertyValue -Object $result -Name "Status" -DefaultValue ""
    $status = if (-not [string]::IsNullOrWhiteSpace($statusValue)) { Get-LocalizedBackupStatus -Status $statusValue } else { "" }
    $message = T "LastBackupText" @(
        (Get-ObjectPropertyValue -Object $result -Name "FinishedAtLocal" -DefaultValue ""),
        (Get-ObjectPropertyValue -Object $result -Name "Source" -DefaultValue ""),
        (Get-ObjectPropertyValue -Object $result -Name "Copied" -DefaultValue 0),
        (Get-ObjectPropertyValue -Object $result -Name "Skipped" -DefaultValue 0),
        (Get-ObjectPropertyValue -Object $result -Name "Failed" -DefaultValue 0),
        (Get-ObjectPropertyValue -Object $result -Name "Total" -DefaultValue 0),
        $backupFolder,
        $status
    )
    $lastError = Get-ObjectPropertyValue -Object $result -Name "LastError"
    if (-not [string]::IsNullOrWhiteSpace($lastError)) {
        $message = "$message`r`n`r`n$lastError"
    }

    [System.Windows.Forms.MessageBox]::Show(
        $message,
        (T "LastBackupResult"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-About {
    [System.Windows.Forms.MessageBox]::Show(
        (T "AboutText" @($AppVersion, $ConfigDir, $StateDir, $LogPath)),
        (T "About"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Export-Diagnostics {
    Ensure-Directory -Path $StateDir
    Ensure-Directory -Path $LogDir
    Load-LastBackupResult

    $lastBackupJson = if ($script:LastBackupResult -ne $null) {
        $script:LastBackupResult | ConvertTo-Json -Depth 8
    }
    else {
        "(none)"
    }

    $lines = @(
        "$AppName $AppVersion",
        "",
        "GeneratedAtLocal: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "ConfigPath: $ConfigPath",
        "StateDir: $StateDir",
        "ManifestPath: $ManifestPath",
        "LastBackupResultPath: $LastBackupResultPath",
        "LogPath: $LogPath",
        "StartupShortcutEnabled: $(Test-StartupShortcutEnabled)",
        "BackupRoot: $($script:Config.BackupRoot)",
        "AutoBackupEnabled: $($script:Config.AutoBackupEnabled)",
        "BackupStartMode: $($script:Config.BackupStartMode)",
        "AutoScanOnStartup: $($script:Config.AutoScanOnStartup)",
        "ShowBackupSummary: $($script:Config.ShowBackupSummary)",
        "MuteNotificationSound: $($script:Config.MuteNotificationSound)",
        "SplitByMediaType: $($script:Config.SplitByMediaType)",
        "GroupBySourceDevice: $($script:Config.GroupBySourceDevice)",
        "PreserveSourceStructure: $($script:Config.PreserveSourceStructure)",
        "OpenFolderAfterBackup: $($script:Config.OpenFolderAfterBackup)",
        "MinFileSizeBytes: $($script:Config.MinFileSizeBytes)",
        "ExcludedFolders: $((@($script:Config.ExcludedFolders) -join ', '))",
        "FileExtensions: $((@($script:Config.FileExtensions) -join ', '))",
        "TrustedSourcesCount: $(@($script:Config.TrustedSources).Count)",
        "IgnoredSourcesCount: $(@($script:Config.IgnoredSources).Count)",
        "",
        "LastBackupResult:",
        $lastBackupJson
    )

    $diagnosticsPath = Join-Path $StateDir "diagnostics.txt"
    Set-Content -LiteralPath $diagnosticsPath -Value ($lines -join [Environment]::NewLine) -Encoding UTF8

    try {
        [System.Windows.Forms.Clipboard]::SetText(($lines -join [Environment]::NewLine))
    }
    catch {
        Write-Log -Level "WARN" -Message "Failed to copy diagnostics to clipboard: $($_.Exception.Message)"
    }

    [System.Windows.Forms.MessageBox]::Show(
        (T "DiagnosticsExported" @($diagnosticsPath)),
        $AppName,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Run-SetupAgain {
    if (Select-BackupRoot -Description (T "ChooseNewBackupFolder")) {
        Show-Notice -Title $AppName -Text (T "SetupUpdated")
    }
}

function Edit-ExcludedFolders {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "ExcludedFolders"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 520, 340
    $form.Icon = Get-TrayIcon
    $form.Font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", 9

    $promptLabel = New-Object System.Windows.Forms.Label
    $promptLabel.Text = T "EditExcludedFoldersPrompt"
    $promptLabel.Location = New-Object System.Drawing.Point -ArgumentList 16, 16
    $promptLabel.Size = New-Object System.Drawing.Size -ArgumentList 488, 44
    $form.Controls.Add($promptLabel)

    $foldersText = New-Object System.Windows.Forms.TextBox
    $foldersText.Location = New-Object System.Drawing.Point -ArgumentList 16, 66
    $foldersText.Size = New-Object System.Drawing.Size -ArgumentList 488, 210
    $foldersText.Multiline = $true
    $foldersText.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $foldersText.AcceptsReturn = $true
    $foldersText.WordWrap = $true
    $foldersText.Text = (@($script:Config.ExcludedFolders) | Sort-Object) -join [Environment]::NewLine
    $form.Controls.Add($foldersText)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = T "Save"
    $saveButton.Location = New-Object System.Drawing.Point -ArgumentList 298, 294
    $saveButton.Size = New-Object System.Drawing.Size -ArgumentList 96, 30
    $saveButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Controls.Add($saveButton)
    $form.AcceptButton = $saveButton

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = T "Cancel"
    $cancelButton.Location = New-Object System.Drawing.Point -ArgumentList 408, 294
    $cancelButton.Size = New-Object System.Drawing.Size -ArgumentList 96, 30
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)
    $form.CancelButton = $cancelButton

    $result = $form.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        $form.Dispose()
        return
    }

    $input = $foldersText.Text
    $form.Dispose()

    $items = @()
    foreach ($value in @(ConvertTo-StringArray @($input))) {
        foreach ($part in ($value -split '[,;\r\n]+')) {
            $folder = ([string]$part).Trim().Trim("\/")
            if (-not [string]::IsNullOrWhiteSpace($folder)) {
                $items += $folder
            }
        }
    }

    $script:Config.ExcludedFolders = @($items | Sort-Object -Unique)
    Save-Config
    Show-Notice -Title $AppName -Text (T "ExcludedFoldersUpdated")
}

function Open-SettingsWindow {
    if ($script:SettingsForm -ne $null -and -not $script:SettingsForm.IsDisposed) {
        $script:SettingsForm.Activate()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = T "Settings"
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size -ArgumentList 640, 488
    $form.Icon = Get-TrayIcon
    $form.Font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", 9

    $backupFolderLabel = New-Object System.Windows.Forms.Label
    $backupFolderLabel.Text = T "BackupFolderLabel"
    $backupFolderLabel.AutoSize = $true
    $backupFolderLabel.Location = New-Object System.Drawing.Point -ArgumentList 16, 12
    $form.Controls.Add($backupFolderLabel)

    $backupFolderText = New-Object System.Windows.Forms.TextBox
    $backupFolderText.Location = New-Object System.Drawing.Point -ArgumentList 16, 34
    $backupFolderText.Size = New-Object System.Drawing.Size -ArgumentList 490, 24
    $backupFolderText.ReadOnly = $true
    $backupFolderText.Text = [string]$script:Config.BackupRoot
    $form.Controls.Add($backupFolderText)

    $changeFolderButton = New-Object System.Windows.Forms.Button
    $changeFolderButton.Text = T "Browse"
    $changeFolderButton.Location = New-Object System.Drawing.Point -ArgumentList 522, 32
    $changeFolderButton.Size = New-Object System.Drawing.Size -ArgumentList 96, 28
    $changeFolderButton.Tag = $backupFolderText
    $changeFolderButton.Add_Click({
        param($sender, $eventArgs)
        if (Select-BackupRoot -Description (T "ChooseNewBackupFolder")) {
            $sender.Tag.Text = [string]$script:Config.BackupRoot
            Show-Notice -Title $AppName -Text (T "BackupFolderUpdated")
        }
    })
    $form.Controls.Add($changeFolderButton)

    $modeGroup = New-Object System.Windows.Forms.GroupBox
    $modeGroup.Text = T "BackupStartModeSetting"
    $modeGroup.Location = New-Object System.Drawing.Point -ArgumentList 16, 74
    $modeGroup.Size = New-Object System.Drawing.Size -ArgumentList 602, 76
    $form.Controls.Add($modeGroup)

    $automaticRadio = New-Object System.Windows.Forms.RadioButton
    $automaticRadio.Text = T "ModeAutomaticOption"
    $automaticRadio.Location = New-Object System.Drawing.Point -ArgumentList 16, 22
    $automaticRadio.Size = New-Object System.Drawing.Size -ArgumentList 550, 22
    $automaticRadio.Checked = ([string]$script:Config.BackupStartMode -ne "ConfirmBeforeBackup")
    $automaticRadio.Add_CheckedChanged({
        param($sender, $eventArgs)
        if ($sender.Checked) {
            $script:Config.BackupStartMode = "Automatic"
            Save-Config
        }
    })
    $modeGroup.Controls.Add($automaticRadio)

    $confirmRadio = New-Object System.Windows.Forms.RadioButton
    $confirmRadio.Text = T "ModeConfirmOption"
    $confirmRadio.Location = New-Object System.Drawing.Point -ArgumentList 16, 48
    $confirmRadio.Size = New-Object System.Drawing.Size -ArgumentList 550, 22
    $confirmRadio.Checked = ([string]$script:Config.BackupStartMode -eq "ConfirmBeforeBackup")
    $confirmRadio.Add_CheckedChanged({
        param($sender, $eventArgs)
        if ($sender.Checked) {
            $script:Config.BackupStartMode = "ConfirmBeforeBackup"
            Save-Config
        }
    })
    $modeGroup.Controls.Add($confirmRadio)

    $startupCheck = New-Object System.Windows.Forms.CheckBox
    $startupCheck.Text = T "StartWithWindows"
    $startupCheck.Location = New-Object System.Drawing.Point -ArgumentList 16, 162
    $startupCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $startupCheck.Checked = Test-StartupShortcutEnabled
    $startupCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        try {
            Set-StartupShortcutEnabled -Enabled ([bool]$sender.Checked)
        }
        catch {
            $sender.Checked = Test-StartupShortcutEnabled
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                $AppName,
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })
    $form.Controls.Add($startupCheck)

    $autoScanCheck = New-Object System.Windows.Forms.CheckBox
    $autoScanCheck.Text = T "AutoScanOnStartup"
    $autoScanCheck.Location = New-Object System.Drawing.Point -ArgumentList 330, 162
    $autoScanCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $autoScanCheck.Checked = [bool]$script:Config.AutoScanOnStartup
    $autoScanCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.AutoScanOnStartup = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($autoScanCheck)

    $summaryCheck = New-Object System.Windows.Forms.CheckBox
    $summaryCheck.Text = T "ShowBackupSummary"
    $summaryCheck.Location = New-Object System.Drawing.Point -ArgumentList 16, 194
    $summaryCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $summaryCheck.Checked = [bool]$script:Config.ShowBackupSummary
    $summaryCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.ShowBackupSummary = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($summaryCheck)

    $muteNotificationCheck = New-Object System.Windows.Forms.CheckBox
    $muteNotificationCheck.Text = T "MuteNotificationSound"
    $muteNotificationCheck.Location = New-Object System.Drawing.Point -ArgumentList 330, 194
    $muteNotificationCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $muteNotificationCheck.Checked = [bool]$script:Config.MuteNotificationSound
    $muteNotificationCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.MuteNotificationSound = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($muteNotificationCheck)

    $splitByTypeCheck = New-Object System.Windows.Forms.CheckBox
    $splitByTypeCheck.Text = T "SplitByMediaType"
    $splitByTypeCheck.Location = New-Object System.Drawing.Point -ArgumentList 16, 226
    $splitByTypeCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $splitByTypeCheck.Checked = [bool]$script:Config.SplitByMediaType
    $splitByTypeCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.SplitByMediaType = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($splitByTypeCheck)

    $groupByDeviceCheck = New-Object System.Windows.Forms.CheckBox
    $groupByDeviceCheck.Text = T "GroupBySourceDevice"
    $groupByDeviceCheck.Location = New-Object System.Drawing.Point -ArgumentList 16, 258
    $groupByDeviceCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $groupByDeviceCheck.Checked = [bool]$script:Config.GroupBySourceDevice
    $groupByDeviceCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.GroupBySourceDevice = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($groupByDeviceCheck)

    $preserveStructureCheck = New-Object System.Windows.Forms.CheckBox
    $preserveStructureCheck.Text = T "PreserveSourceStructure"
    $preserveStructureCheck.Location = New-Object System.Drawing.Point -ArgumentList 330, 226
    $preserveStructureCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $preserveStructureCheck.Checked = [bool]$script:Config.PreserveSourceStructure
    $preserveStructureCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.PreserveSourceStructure = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($preserveStructureCheck)

    $openAfterBackupCheck = New-Object System.Windows.Forms.CheckBox
    $openAfterBackupCheck.Text = T "OpenFolderAfterBackup"
    $openAfterBackupCheck.Location = New-Object System.Drawing.Point -ArgumentList 16, 290
    $openAfterBackupCheck.Size = New-Object System.Drawing.Size -ArgumentList 290, 24
    $openAfterBackupCheck.Checked = [bool]$script:Config.OpenFolderAfterBackup
    $openAfterBackupCheck.Add_CheckedChanged({
        param($sender, $eventArgs)
        $script:Config.OpenFolderAfterBackup = [bool]$sender.Checked
        Save-Config
    })
    $form.Controls.Add($openAfterBackupCheck)

    $minSizeLabel = New-Object System.Windows.Forms.Label
    $minSizeLabel.Text = T "MinFileSizeLabel"
    $minSizeLabel.Location = New-Object System.Drawing.Point -ArgumentList 330, 294
    $minSizeLabel.Size = New-Object System.Drawing.Size -ArgumentList 160, 22
    $form.Controls.Add($minSizeLabel)

    $minSizeInput = New-Object System.Windows.Forms.NumericUpDown
    $minSizeInput.Location = New-Object System.Drawing.Point -ArgumentList 498, 290
    $minSizeInput.Size = New-Object System.Drawing.Size -ArgumentList 120, 24
    $minSizeInput.Minimum = 0
    $minSizeInput.Maximum = 10485760
    $minSizeInput.Value = [decimal]([Math]::Floor([double]$script:Config.MinFileSizeBytes / 1024))
    $minSizeInput.Add_ValueChanged({
        param($sender, $eventArgs)
        $script:Config.MinFileSizeBytes = [int64]$sender.Value * 1024
        Save-Config
    })
    $form.Controls.Add($minSizeInput)

    $editExtensionsButton = New-Object System.Windows.Forms.Button
    $editExtensionsButton.Text = T "EditExtensions"
    $editExtensionsButton.Location = New-Object System.Drawing.Point -ArgumentList 16, 334
    $editExtensionsButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $editExtensionsButton.Add_Click({ Edit-SupportedExtensions })
    $form.Controls.Add($editExtensionsButton)

    $excludedFoldersButton = New-Object System.Windows.Forms.Button
    $excludedFoldersButton.Text = T "ExcludedFolders"
    $excludedFoldersButton.Location = New-Object System.Drawing.Point -ArgumentList 172, 334
    $excludedFoldersButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $excludedFoldersButton.Add_Click({ Edit-ExcludedFolders })
    $form.Controls.Add($excludedFoldersButton)

    $trustedSourcesButton = New-Object System.Windows.Forms.Button
    $trustedSourcesButton.Text = T "ManageTrustedSources"
    $trustedSourcesButton.Location = New-Object System.Drawing.Point -ArgumentList 328, 334
    $trustedSourcesButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $trustedSourcesButton.Add_Click({ Manage-TrustedSources })
    $form.Controls.Add($trustedSourcesButton)

    $configFolderButton = New-Object System.Windows.Forms.Button
    $configFolderButton.Text = T "OpenConfigFolder"
    $configFolderButton.Location = New-Object System.Drawing.Point -ArgumentList 16, 378
    $configFolderButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $configFolderButton.Add_Click({ Open-ConfigFolder })
    $form.Controls.Add($configFolderButton)

    $historyButton = New-Object System.Windows.Forms.Button
    $historyButton.Text = T "BackupHistory"
    $historyButton.Location = New-Object System.Drawing.Point -ArgumentList 484, 334
    $historyButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $historyButton.Add_Click({ Show-LastBackupResult })
    $form.Controls.Add($historyButton)

    $logFolderButton = New-Object System.Windows.Forms.Button
    $logFolderButton.Text = T "OpenLogFolder"
    $logFolderButton.Location = New-Object System.Drawing.Point -ArgumentList 172, 378
    $logFolderButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $logFolderButton.Add_Click({ Open-LogFolder })
    $form.Controls.Add($logFolderButton)

    $diagnosticsButton = New-Object System.Windows.Forms.Button
    $diagnosticsButton.Text = T "ExportDiagnostics"
    $diagnosticsButton.Location = New-Object System.Drawing.Point -ArgumentList 328, 378
    $diagnosticsButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $diagnosticsButton.Add_Click({ Export-Diagnostics })
    $form.Controls.Add($diagnosticsButton)

    $aboutButton = New-Object System.Windows.Forms.Button
    $aboutButton.Text = T "About"
    $aboutButton.Location = New-Object System.Drawing.Point -ArgumentList 484, 378
    $aboutButton.Size = New-Object System.Drawing.Size -ArgumentList 150, 30
    $aboutButton.Add_Click({ Show-About })
    $form.Controls.Add($aboutButton)

    $setupAgainButton = New-Object System.Windows.Forms.Button
    $setupAgainButton.Text = T "RunSetupAgain"
    $setupAgainButton.Location = New-Object System.Drawing.Point -ArgumentList 16, 442
    $setupAgainButton.Size = New-Object System.Drawing.Size -ArgumentList 180, 30
    $setupAgainButton.Tag = $backupFolderText
    $setupAgainButton.Add_Click({
        param($sender, $eventArgs)
        Run-SetupAgain
        $sender.Tag.Text = [string]$script:Config.BackupRoot
    })
    $form.Controls.Add($setupAgainButton)

    $cleanupButton = New-Object System.Windows.Forms.Button
    $cleanupButton.Text = T "CleanupData"
    $cleanupButton.Location = New-Object System.Drawing.Point -ArgumentList 216, 442
    $cleanupButton.Size = New-Object System.Drawing.Size -ArgumentList 180, 30
    $cleanupButton.BackColor = [System.Drawing.Color]::FromArgb(190, 38, 38)
    $cleanupButton.ForeColor = [System.Drawing.Color]::White
    $cleanupButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cleanupButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(140, 28, 28)
    $cleanupButton.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(220, 54, 54)
    $cleanupButton.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(150, 28, 28)
    $cleanupButton.Add_Click({ Invoke-Cleanup -ExitAfterCleanup })
    $form.Controls.Add($cleanupButton)

    $closeButton = New-Object System.Windows.Forms.Button
    $closeButton.Text = T "Close"
    $closeButton.Location = New-Object System.Drawing.Point -ArgumentList 518, 442
    $closeButton.Size = New-Object System.Drawing.Size -ArgumentList 100, 30
    $closeButton.Add_Click({ param($sender, $eventArgs) $sender.FindForm().Close() })
    $form.Controls.Add($closeButton)

    $form.Add_FormClosed({ $script:SettingsForm = $null })
    $script:SettingsForm = $form
    [void]$form.Show()
}

function New-TrayIcon {
    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Icon = Get-TrayIcon
    $notifyIcon.Text = $AppName
    $notifyIcon.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip

    $scanItem = $menu.Items.Add((T "ScanNow"))
    $scanItem.Add_Click({ Invoke-ScanAll -Force })

    $autoBackupItem = $menu.Items.Add((Get-AutoBackupMenuText))
    $autoBackupItem.Add_Click({ param($sender, $eventArgs) Toggle-AutoBackup -MenuItem $sender })

    $openItem = $menu.Items.Add((T "OpenBackupFolder"))
    $openItem.Add_Click({ Open-BackupRoot })

    $openRecentItem = $menu.Items.Add((T "OpenRecentBackupFolder"))
    $openRecentItem.Add_Click({ Open-RecentBackupFolder })

    $settingsItem = $menu.Items.Add((T "Settings"))
    $settingsItem.Add_Click({ Open-SettingsWindow })

    $logItem = $menu.Items.Add((T "ViewLog"))
    $logItem.Add_Click({ Open-Log })

    [void]$menu.Items.Add("-")

    $exitItem = $menu.Items.Add((T "Exit"))
    $exitItem.Add_Click({
        $script:NotifyIcon.Visible = $false
        $script:NotifyIcon.Dispose()
        [System.Windows.Forms.Application]::Exit()
    })

    $notifyIcon.ContextMenuStrip = $menu
    $notifyIcon.Add_DoubleClick({ Open-BackupRoot })
    return $notifyIcon
}

function Start-App {
    $mutex = New-Object System.Threading.Mutex($false, "Local\UsbPhotoBackupTray")
    if (-not $mutex.WaitOne(0, $false)) {
        [System.Windows.Forms.MessageBox]::Show(
            (T "AlreadyRunning"),
            $AppName,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        $mutex.Dispose()
        return
    }

    try {
        Load-Config
        Load-Manifest
        Load-LastBackupResult
        $script:NotifyIcon = New-TrayIcon

        if (-not (Ensure-InitialBackupRoot)) {
            Write-Log -Level "WARN" -Message "No backup root selected. Exiting."
            return
        }

        if (-not $StartMinimized) {
            Show-Notice -Title $AppName -Text (T "RunningInTray")
        }

        $script:ScanTimer = New-Object System.Windows.Forms.Timer
        $script:ScanTimer.Interval = [Math]::Max(3, [int]$script:Config.ScanIntervalSeconds) * 1000
        $script:ScanTimer.Add_Tick({ Invoke-ScanAll })
        $script:ScanTimer.Start()

        if ([bool]$script:Config.AutoScanOnStartup) {
            Invoke-ScanAll
        }
        [System.Windows.Forms.Application]::Run()
    }
    finally {
        if ($script:NotifyIcon -ne $null) {
            $script:NotifyIcon.Visible = $false
            $script:NotifyIcon.Dispose()
        }
        if ($script:ScanTimer -ne $null) {
            $script:ScanTimer.Stop()
            $script:ScanTimer.Dispose()
        }
        $mutex.ReleaseMutex() | Out-Null
        $mutex.Dispose()
    }
}

if ($Uninstall) {
    Invoke-Cleanup | Out-Null
}
else {
    Start-App
}

