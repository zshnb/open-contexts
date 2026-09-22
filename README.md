# Open Contexts

Open Contexts 是付费 macOS 窗口管理软件 [Contexts](https://contexts.co/) 的非官方开源复刻版，主要还原其侧栏和窗口切换体验。

## 核心功能

| Contexts 功能 | Open Contexts 实现 |
| --- | --- |
| 窗口级切换 | 以窗口而不是应用为单位展示和切换，并跟踪最近使用顺序（MRU） |
| 屏幕边缘侧栏 | 支持左侧或右侧、始终显示或移到边缘时唤出 |
| 键盘切换器 | `⌘Tab` 切换所有窗口，`Command + 反引号` 切换当前应用窗口；支持 `⇧Tab`、方向键、`Esc` 与松开 `⌘` 确认 |
| 窗口激活 | 激活最小化或隐藏的窗口时尝试恢复显示 |
| 窗口信息 | 显示应用图标、窗口标题与系统可读取的 Dock 通知角标 |
| 多显示器与跨 Space | 已实现，仍需在更多设备和应用中验证 |

### Open Contexts 独有功能：保存自定义窗口分组

原版 Contexts 不支持保存自定义窗口分组，Open Contexts 在复刻核心体验之外增加了这项功能：

- 创建、重命名和删除分组，拖动窗口或分组调整顺序。
- 重启后恢复分组名称和顺序，以及可匹配窗口的分组、顺序和侧栏位置。
- 使用 Swift、AppKit 和 SwiftUI 原生实现，无第三方依赖。

目前尚未复刻 Contexts 的搜索、Fast Search、触控板手势和按 Space 筛选功能。多显示器、跨 Space 和全屏场景已有相应实现，但仍需在更多真实环境中验证。

## 安装与首次运行

系统要求：macOS 13 或更高版本。macOS 13 等较旧版本尚未完成实机验证。

1. 从 [GitHub Releases](https://github.com/zshnb/open-contexts/releases) 下载 DMG。
2. 打开 DMG，将 `OpenContexts.app` 拖入 `/Applications`。
3. 启动 Open Contexts。
4. 从菜单栏打开设置，按照提示前往“系统设置 → 隐私与安全性 → 辅助功能”，授权 Open Contexts。

辅助功能权限用于发现和切换窗口，以及接管快捷键。未授权或应用退出时，Open Contexts 不会接管 `⌘Tab`。应用更新后如果权限失效，请在辅助功能列表中移除 Open Contexts，再重新添加并授权。

### macOS 提示应用无法打开

未经 Developer ID 签名和 Apple 公证的构建可能被 Gatekeeper 拦截。确认安装包来自本仓库后，在终端执行：

```sh
xattr -dr com.apple.quarantine "/Applications/OpenContexts.app"
```

## 使用

- `⌘Tab`：打开所有窗口切换器；继续按 `Tab` 或按 `↓` 向前选择，按 `⇧Tab` 或 `↑` 向后选择。
- `Command + 反引号`：打开当前应用的窗口切换器。
- `Esc`：取消切换；松开 `⌘`：激活选中的窗口。
- 侧栏底部：新建分组。
- 右键分组标题：重命名或删除分组。
- 拖动窗口：移入分组或调整顺序；拖动分组标题：调整分组顺序。
- 菜单栏设置：选择侧栏位于左侧或右侧，以及始终显示或靠近屏幕边缘时显示。

测试时请先退出其他接管 `⌘Tab` 的工具，避免全局快捷键冲突。

## 从源码构建

需要 macOS 13 或更高版本，以及支持 Swift 5.9 的 Xcode Command Line Tools。

没有 Apple 开发证书时，使用 ad-hoc 签名构建：

```sh
git clone https://github.com/zshnb/open-contexts.git
cd open-contexts
swift test
SIGNING_MODE=adhoc ./scripts/build-app.sh
dist/OpenContexts.app/Contents/MacOS/OpenContexts --self-check
dist/OpenContexts.app/Contents/MacOS/OpenContexts --ui-self-check
open dist/OpenContexts.app
```

`--ui-self-check` 需要已登录的图形会话。它会短暂创建并关闭侧栏和切换器，不会请求辅助功能权限或安装全局快捷键。

默认运行 `./scripts/build-app.sh` 会使用钥匙串中唯一的 Apple Development 证书。存在多个证书时，通过 `CODE_SIGN_IDENTITY` 指定证书 SHA-1 或完整名称。稳定的开发签名可减少重建后辅助功能授权失效；Apple Development 签名仍不等于面向公众分发所需的 Developer ID 签名与 Apple 公证。

## 数据

分组与可恢复窗口的期望位置保存在：

```text
~/Library/Application Support/OpenContexts/groups.json
```

应用优先使用应用标识和文档 URL 匹配窗口，没有文档 URL 时使用标题。无标题且无文档地址的窗口，以及“未分组”中存在匹配歧义的记录，仍可在本次运行中显示和拖动，但不会写入历史记录。自定义分组中可匹配的历史位置会保留。运行中修改窗口标题不会重新分组，已关闭且无法恢复的旧记录会自动清理。

## 开发与贡献

欢迎提交 Issue 和 Pull Request。

<details>
<summary>发布与签名</summary>

推送 `v*` 标签后，GitHub Actions 会构建 Universal DMG，并将 DMG 和 `SHA256SUMS.txt` 发布到 GitHub Releases。

正式发布默认使用 Developer ID 签名与 Apple 公证，需要配置 `APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID` 和 `APPLE_APP_SPECIFIC_PASSWORD`。缺少凭据时流水线会停止，不会自动降级签名。

内部测试包可将仓库变量 `RELEASE_SIGNING_MODE` 显式设为 `adhoc`；这类产物未经 Apple 公证。删除该变量或设为 `developer-id` 可恢复正式发布流程。

</details>

## 许可证

本项目采用 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。允许在遵守许可证条款的前提下商业使用、修改和分发。
