# 随插备份 / Plug & Backup

<p align="center">
  <img src="assets/usb-backup.png" alt="随插备份 / Plug & Backup" width="160">
</p>

[English README](./README.en.md)

一个 Windows 便携托盘工具，用来自动备份 U 盘、读卡器、相机内存卡和外接移动硬盘中的照片、视频和相机 RAW 文件。

它的目标很简单：插入设备，确认信任，然后把媒体文件安全地复制到你的备份目录。程序只复制文件，不删除原文件，默认也不会向内存卡或 USB 设备写入隐藏标记文件。

## 下载

请从 GitHub Releases 下载 `PlugAndBackup.exe`。

- 便携版，无需安装。
- 运行时不需要额外软件。
- 1.0 版本未做代码签名，首次运行时 Windows SmartScreen 可能会提示风险，这是未签名软件的常见现象。

## 主要功能

- 常驻系统托盘，后台监听已连接设备。
- 支持中文 / 英文界面，跟随 Windows 显示语言。
- 支持照片、视频和常见相机 RAW 格式。
- 自动或手动扫描 U 盘、读卡器、相机卡和外接硬盘。
- 使用本机复合指纹识别已信任来源，不依赖写入内存卡。
- 支持“信任并备份”“本次跳过”“永久跳过”。
- 支持自动备份或插入后确认再备份。
- 使用 SHA-256 内容哈希去重。
- 同名不同内容自动改名，不覆盖已有文件。
- 可按日期、设备、照片 / 视频 / RAW、原设备目录结构归档。
- 可设置开机启动、通知静音、最小文件大小、排除文件夹和自定义扩展名。
- 提供备份历史、打开最近备份位置、日志文件夹、诊断信息导出和清理/卸载数据功能。

## 默认支持格式

- 图片：`jpg/jpeg/png/heic/webp/gif/bmp/tif/tiff`
- 视频：`mp4/mov/avi/mkv/m4v/3gp/wmv/mts/m2ts`
- RAW：`dng/cr2/cr3/nef/arw/raf/orf/rw2/pef/sr2/x3f/crw/iiq/3fr`

支持格式可以在设置窗口中自定义。

## 快速使用

1. 下载并运行 `PlugAndBackup.exe`。
2. 首次启动时选择备份文件夹。
3. 在设置窗口中按需要调整备份模式和归档选项。
4. 插入 USB 设备、读卡器或移动硬盘。
5. 在弹窗中选择信任、跳过或永久跳过。

程序启动后会显示在系统托盘。右键托盘图标可以立即扫描、暂停自动备份、打开备份目录、打开最近备份位置、进入设置或退出。

## 备份目录结构

默认结构：

```text
<备份目录>\YYYY\YYYY-MM-DD\文件名
```

可选组合：

```text
<备份目录>\<设备名>\Photos\YYYY\YYYY-MM-DD\文件名
<备份目录>\<设备名>\Videos\YYYY\YYYY-MM-DD\文件名
<备份目录>\<设备名>\RAW\YYYY\YYYY-MM-DD\文件名
```

如果两个不同设备使用相同名称，程序会自动追加短指纹后缀，例如 `CAMERA-8F3A2C`。

## 安全边界

- 不删除 USB、内存卡或备份目录里的文件。
- 默认不向 USB 或内存卡写入隐藏标记文件。
- 不扫描 Windows 系统盘。
- 为避免误扫本机数据，只自动处理可移动盘，或可确认为 USB/SD/MMC 总线的外接 Fixed 盘。
- 如果备份目录在 NAS 或网络路径上且暂时离线，程序启动时不会强制重选目录；只有在发现需要备份的设备时才会提示暂不备份或重新选择位置。
- MTP 手机如果没有 Windows 盘符，当前版本不会扫描。
- 当前版本使用文件修改时间归档，暂不读取 EXIF 或视频拍摄时间元数据。

## 配置和日志

- 配置：`%APPDATA%\UsbPhotoBackup\config.json`
- 去重索引：`%LOCALAPPDATA%\UsbPhotoBackup\manifest.json`
- 最近备份结果：`%LOCALAPPDATA%\UsbPhotoBackup\last-backup.json`
- 日志：`%LOCALAPPDATA%\UsbPhotoBackup\logs\backup.log`

可以在设置窗口中执行“清理/卸载数据”。该操作只清理本机配置、日志、去重索引和开机启动快捷方式，不会删除已备份文件。

## 从源码运行

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\UsbPhotoBackup.ps1
```

## 构建

构建机器需要安装 PS2EXE：

```powershell
Install-Module ps2exe -Scope CurrentUser
```

然后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-PortableExe.ps1
```

输出文件位于 `dist\`。构建说明见 [BUILD.md](./BUILD.md)。

## 许可证

MIT License. See [LICENSE](./LICENSE).
