# 随插备份 / Plug & Backup

一个零依赖的 Windows 托盘工具，用来自动备份已授权 USB 设备、读卡器或移动硬盘里的照片和视频。第一版目标是便携单 exe，不做传统安装器。

## 下载

请从 GitHub Releases 下载 `PlugAndBackup.exe`。这是便携版程序，不需要安装，下载后直接运行即可。

1.0 版本未做代码签名，首次运行时 Windows SmartScreen 可能会提示风险；这是未签名软件的常见现象。

## 功能

- 常驻系统托盘。
- 根据 Windows 显示语言自动切换中文/英文界面。
- 首次运行选择备份目录，并自动打开设置窗口完成初始配置。
- 插入 U 盘、读卡器或移动硬盘后询问是否信任该设备。
- 后台会持续运行并监听设备变化；同一个设备插入后只会自动备份一次，完成后不会反复扫描。
- 使用本机保存的复合指纹识别已信任来源，默认不向内存卡或 USB 设备写入隐藏标记文件。
- 自动复制图片和视频，保留 USB 原文件。
- 按文件修改日期归档到 `YYYY\YYYY-MM-DD`。
- 使用 SHA-256 内容哈希去重，同名不同内容会自动改名。
- 支持在设置窗口里自定义要备份的文件扩展名。
- 可从右键菜单暂停/恢复自动备份、打开最近备份位置，并在设置窗口里选择插入后是否先确认、控制完成摘要、通知静音、管理已信任来源。
- 支持开机启动、启动时扫描、备份历史、关于信息、按类型分目录、保留原设备目录结构、最小文件大小和排除文件夹。
- 可选择按不同设备/来源建立独立备份文件夹；同名不同设备会自动追加短指纹区分。
- 使用 `assets\usb-backup.ico` 作为当前托盘、快捷方式和 exe 图标；`assets\usb-backup-simplified.ico` 是小尺寸备用图标。

支持格式：

- 图片：`jpg/jpeg/png/heic/webp/gif/bmp/tif/tiff`
- 视频：`mp4/mov/avi/mkv/m4v/3gp/wmv/mts/m2ts`
- RAW：`dng/cr2/cr3/nef/arw/raf/orf/rw2/pef/sr2/x3f/crw/iiq/3fr`

## 普通使用

打包后直接运行：

```text
PlugAndBackup.exe
```

首次启动会先选择备份目录，然后自动打开 `Settings` / `设置` 窗口，方便一次性调整备份模式、通知静音、开机启动、归档规则等选项。

启动后会出现在系统托盘。右键托盘图标可以：

- `Scan now` / `立即扫描`：手动强制扫描当前已连接设备。
- `Pause automatic backup` / `暂停自动备份`：暂停自动处理新插入设备；手动立即扫描仍可使用。
- `Open backup folder`：打开备份目录。
- `Open recent backup folder` / `打开最近备份位置`：打开最近一次复制或跳过文件所在的备份目录。
- `Settings` / `设置`：打开独立设置窗口。
- `View log`：查看日志文件。
- `Exit`：退出。

设置窗口可以：

- 选择 `Backup mode: automatic` / `备份模式：自动备份`，或 `Backup mode: confirm after insert` / `备份模式：插入后确认`。
- 控制备份完成后是否弹出结果摘要。
- 选择 `Mute notification sound` / `系统通知静音`，让托盘通知弹窗不播放提示音。
- 开启 `Start with Windows` / `开机启动`。
- 开启或关闭 `Scan connected devices when the app starts` / `启动时自动检查已连接设备`。
- 开启 `Separate Photos / Videos / RAW folders` / `按照片 / 视频 / RAW 分目录`。
- 开启 `Separate folders by device` / `按设备分文件夹保存`。
- 开启 `Preserve source folder structure` / `保留原设备目录结构`。
- 设置最小文件大小和排除文件夹。
- 查看和更改备份目录。
- 编辑支持格式、管理信任来源、查看备份历史、打开配置文件夹、打开日志文件夹、导出诊断信息、查看关于信息。
- 执行 `Clean up / uninstall data` / `清理/卸载数据`。

## 高级/开发运行

未打包时，可以在 PowerShell 中进入本目录运行：

```powershell
cd C:\Tools\PlugAndBackup
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\UsbPhotoBackup.ps1
```

打包说明见 [BUILD.md](./BUILD.md)。

## 设备识别

工具默认不写入内存卡。授权信息保存在本机配置中，识别时会组合以下信息形成复合指纹：

- 原生存储描述符：序列号、厂商、产品名、产品版本、总线类型、是否可移除。
- WMI/CIM 可读时提供的硬件序列号、硬件 ID、型号等补充信息。
- Volume GUID、容量、盘类型等来源身份信息。
- 卷序列号、文件系统、卷标、Windows 内部设备路径等卷状态信息。

硬件信息会优先通过 Windows `DeviceIoControl` 读取，WMI/CIM 只作为补充；如果系统权限拒绝 WMI，工具仍会尽量读取原生存储描述符。工具会把识别分成两层：`SourceIdentityHash` 用于判断是不是同一个相机存储槽、移动硬盘或内存卡来源；`VolumeStateHash` 只记录卷序列号、卷标、内部设备路径等可能随格式化或挂载变化的状态。若来源身份稳定匹配，工具会自动备份；若只匹配到较弱信息，工具会询问是否更新本机指纹。

如果同一张内存卡通过不同相机、读卡器或 USB 模式连接，硬件来源身份可能完全不同。此时工具会使用 `CrossConnectionHash`（卷序列号、文件系统、容量、盘类型）进行跨连接方式判断：匹配时不会自动放行，而是提示“可能是同一张内存卡通过不同方式连接”。确认后，新的连接方式会作为同一信任来源的别名保存，后续不需要反复确认。内存卡格式化、更换读卡器、重新分区或 Windows 权限限制，都可能导致需要重新确认一次。

旧版本曾写入的 `.usb-photo-backup-device.json` 会被只读兼容识别，但新版本不会主动创建或修改它。

遇到未保存过的来源时，可以选择 `Trust and back up` / `信任并备份`、`Skip this time` / `本次跳过` 或 `Always skip` / `永久跳过`。永久跳过只保存在本机配置中，不会写入或修改 USB/内存卡；以后自动扫描和手动扫描都会跳过该来源。

可以从设置窗口的 `Manage trusted/skipped sources` / `管理信任/跳过来源` 删除单个信任或跳过来源。列表中 `T1` 表示信任来源，`S1` 表示跳过来源；删除后不会删除备份文件，也不会修改内存卡。删除跳过来源后，下次插入会重新询问。

## 备份模式

设置窗口中的备份模式控制“设备插入后是否立刻开始备份”：

- `Backup mode: automatic` / `备份模式：自动备份`：信任来源识别通过后自动备份。
- `Backup mode: confirm after insert` / `备份模式：插入后确认`：信任来源识别通过后弹窗确认；选择“否”会跳过本次插入，拔出后重新插入才会再次询问。

`Pause automatic backup` / `暂停自动备份` 是总开关。暂停后不会自动备份，也不会弹出插入确认；`Scan now` / `立即扫描` 是手动操作，会绕过插入确认并直接扫描。

## 自定义格式

右键托盘图标，打开 `Settings` / `设置`，再选择 `Edit supported formats` / `编辑支持格式`。编辑窗口支持一行一个扩展名，也可以使用逗号或空格分隔，例如：

```text
jpg
jpeg
mp4
mov
arw
dng
```

扩展名会自动转为小写、补齐开头的点并去重，保存后立即生效。

## 归档选项

默认归档结构为：

```text
<备份目录>\YYYY\YYYY-MM-DD\文件名
```

可在设置中开启：

- 按设备分文件夹：`<备份目录>\<设备名>\YYYY\YYYY-MM-DD`。如果两个不同设备使用同一个卷标/名称，后出现的同名设备会自动追加短指纹，例如 `CAMERA-8F3A2C`
- 按类型分目录：`Photos\YYYY\YYYY-MM-DD`、`Videos\YYYY\YYYY-MM-DD`、`RAW\YYYY\YYYY-MM-DD`
- 保留原设备目录结构：日期目录下继续保留 `DCIM`、`PRIVATE` 等来源路径
- 最小文件大小：跳过过小的缩略图或缓存文件
- 排除文件夹：默认跳过 `System Volume Information` 和 `$RECYCLE.BIN`

如果同时开启按设备和按类型分目录，结构为：

```text
<备份目录>\<设备名>\Photos\YYYY\YYYY-MM-DD\文件名
```

按设备分目录只影响之后新备份的文件，不会自动迁移已有备份。内容去重仍然是全局 SHA-256 去重：同一个文件内容已经备份过时，不会为了不同设备文件夹重复复制。

## 开机启动

运行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\Install-Startup.ps1
```

这会在当前用户的 Windows Startup 文件夹里创建一个快捷方式。以后登录 Windows 时会自动启动托盘程序。

如果 `assets\usb-backup.ico` 存在，开机启动快捷方式也会使用这个图标。备用图标保存在 `assets\usb-backup-simplified.ico`。

也可以直接在设置窗口里勾选 `Start with Windows` / `开机启动`。

## 清理/卸载数据

可以从设置窗口选择 `Clean up / uninstall data` / `清理/卸载数据`，也可以运行：

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\UsbPhotoBackup.ps1 -Uninstall
```

清理前会连续弹出两次确认；任意一次取消都不会删除文件。

清理功能会删除：

- `%APPDATA%\UsbPhotoBackup`
- `%LOCALAPPDATA%\UsbPhotoBackup`
- 当前用户 Startup 文件夹里的开机启动快捷方式

清理功能不会删除：

- 已备份到目标目录的照片和视频
- USB 设备上的旧版 `.usb-photo-backup-device.json` 隐藏标记文件
- 工具脚本或未来打包出的 exe 文件本身

运行时不需要安装额外软件。打包成便携单 exe 后，仍然通过设置窗口或 `-Uninstall` 参数清理本机数据；删除 exe 文件即可移除程序本体。

打包后也可以运行：

```powershell
.\PlugAndBackup.exe -Uninstall
```

## 配置和日志位置

- 配置：`%APPDATA%\UsbPhotoBackup\config.json`
- 去重索引：`%LOCALAPPDATA%\UsbPhotoBackup\manifest.json`
- 最近备份结果：`%LOCALAPPDATA%\UsbPhotoBackup\last-backup.json`
- 诊断信息导出：`%LOCALAPPDATA%\UsbPhotoBackup\diagnostics.txt`
- 日志：`%LOCALAPPDATA%\UsbPhotoBackup\logs\backup.log`

## 注意事项

- v1 使用文件修改时间作为归档日期，不读取 EXIF 或视频拍摄元数据。
- 只支持 Windows 识别为盘符的 U 盘、读卡器或移动硬盘；MTP 手机如果没有盘符，v1 不会扫描。
- 为了避免误扫本机数据，程序只会自动处理可移动盘，或可确认为 USB/SD/MMC 总线的外接 Fixed 盘；本机 SATA/NVMe 等内部硬盘分区会被排除。
- 程序不会扫描 Windows 系统盘；为了避免循环备份，也不会扫描备份目录所在盘。
- 备份是复制模式，不会删除 USB 原文件。
- 1.0 便携 exe 未做代码签名，首次运行时 Windows SmartScreen 可能会提示风险；这是未签名软件的常见现象。
