# Rin

Mac 菜单栏资源监控工具。界面按 claude.ai 画布「Hum 视觉方向」实现：每个模块一个菜单栏小工具和下拉面板，主窗口分「监视器」和「设置」两组。

## 构建和运行

需要 Xcode 27 和 XcodeGen（`brew install xcodegen`）。`Rin.xcodeproj` 由 `project.yml` 生成，新增或删除源文件后要重新生成。

```bash
xcodegen generate
```

```bash
xcodebuild -project Rin.xcodeproj -scheme Rin -configuration Release -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Release/Rin.app
```

也可以直接用 Xcode 打开 `Rin.xcodeproj` 运行。最低系统版本 macOS 14，不用沙盒（要读 SMC、IOKit 和进程信息），本地构建用临时签名。

## 目录

| 目录 | 内容 |
|---|---|
| `Rin/Readers` | 数据采集：CPU、内存、网络、磁盘、电池和蓝牙设备、SMC 温度风扇、IOReport 功耗和 GPU 频率、进程排行 |
| `Rin/Core` | 采样调度（`Monitor`）、历史记录（5 分钟到 7 天，峰值回看）、设置、警报、结束进程、主题色、文案 |
| `Rin/MenuBar` | 菜单栏小工具（每个模块 4 种样式 + 合并模式）和下拉面板窗口 |
| `Rin/Popovers` | 各模块下拉面板和合并模式的总面板 |
| `Rin/Window` | 主窗口：概览、7 个监视器页、通用 / 菜单栏 / 各模块 / 警报 / 关于 |
| `Rin/Resources` | 中英文文案（`*.lproj/Localizable.strings`）、图标 |
| `Rin/Debug` | 只在调试版里编译的截图工具 |

## 约定

- 界面文案都放在 `Rin/Core/L10n.swift`，译文在 `Localizable.strings`。改完运行 `python3 scripts/check-l10n.py` 检查两种语言的键是否齐全。
- 菜单栏每次刷新渲染成一张图片交给系统：单色时用模板图，深浅菜单栏由系统着色；画面没变就不更新，多显示器时开销最小。
- 进程的网络流量（`nettop`）、GPU 占用和其他用户的进程（`ps`）只在对应面板或页面打开时采集。

## 调试截图

调试版支持两个命令，输出 PNG 方便对照设计稿：

```bash
build/DerivedData/Build/Products/Debug/Rin.app/Contents/MacOS/Rin --snapshot /tmp/rin-snap
```

离屏渲染所有菜单栏样式、下拉面板和主窗口页面（浅色和深色各一套）。

```bash
build/DerivedData/Build/Products/Debug/Rin.app/Contents/MacOS/Rin --dump-live /tmp/rin-live
```

正常启动后导出真实的状态栏按钮、逐个点开的面板和主窗口页面。

重新生成应用图标：

```bash
swift scripts/make-icon.swift Rin/Resources/Assets.xcassets/AppIcon.appiconset
```
