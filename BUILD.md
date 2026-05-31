# Build

随插备份 / Plug & Backup 1.0 建议打包为便携单 exe，不做传统安装器。

## Output

构建输出目录：

```text
dist\
  PlugAndBackup.exe
  README.md
  CHANGELOG.md
```

程序运行时仍使用以下本机数据目录，打包不会改变它们：

```text
%APPDATA%\UsbPhotoBackup
%LOCALAPPDATA%\UsbPhotoBackup
```

## Build Tool

用户运行软件不需要额外依赖。构建机器需要安装 PS2EXE 模块：

```powershell
Install-Module ps2exe -Scope CurrentUser
```

如果构建机器不能联网，可以先在其他机器下载模块，再复制到构建机器的 PowerShell 模块目录。

## Build Command

在项目目录运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-PortableExe.ps1
```

构建脚本会使用：

- 入口脚本：`UsbPhotoBackup.ps1`
- exe 名称：`PlugAndBackup.exe`
- 图标：`assets\usb-backup.ico`
- 版本：`1.0.0`
- 无控制台窗口
- STA 模式，保证 Windows Forms 托盘和剪贴板功能正常

## Release Checklist

- 首次启动能选择备份目录，并自动打开设置窗口。
- 托盘图标、右键菜单、设置窗口、关于窗口显示正常。
- `-Uninstall` 参数和设置里的清理/卸载数据可用。
- 内部硬盘分区不会被识别为备份来源。
- U 盘、读卡器、外接移动硬盘能进入授权/跳过/备份流程。
- 按设备分目录、按类型分目录、保留原目录结构组合可用。
- `dist\README.md` 和 `dist\CHANGELOG.md` 已随 exe 一起更新。

未签名 exe 首次运行可能触发 Windows SmartScreen。1.0 可以先不签名；后续若要正式分发，再考虑代码签名证书。
