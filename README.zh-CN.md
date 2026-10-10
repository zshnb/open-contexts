[English](README.md) | **简体中文**

<h1 align="center"><img src="assets/AppIcon.png" alt="Open Contexts 图标" width="48" height="48" align="absbottom"> Open Contexts — 免费开源的 Mac 窗口切换器</h1>

Open Contexts 是**免费开源的 macOS 窗口切换器**，支持按应用名或窗口标题搜索，提供常驻应用栏和可保存的窗口分组。用 `⌘Tab` 在单个窗口之间切换，在侧边栏按任务整理窗口，并自定义键盘快捷键。全部功能免费，无需账户或订阅。

[下载 macOS 版本](https://github.com/zshnb/open-contexts/releases/latest) · [官方网站](https://opencontexts.zshnb.com/zh/) · [如何在 Mac 上切换窗口](https://opencontexts.zshnb.com/zh/guides/switch-between-windows-on-mac/) · [Mac 窗口切换器对比](https://opencontexts.zshnb.com/zh/compare/)

## 在 Mac 上切换与整理窗口

- **直接选择窗口。** macOS 原生 `⌘Tab` 在应用之间切换；Open Contexts 按最近使用顺序列出单个窗口，包括同一应用的多个窗口。
- **随时访问窗口。** 将应用栏放在屏幕左侧、右侧或底部，选择始终显示或鼠标到达边缘时显示。
- **按任务整理窗口。** 为代码、研究或聊天创建分组，拖动窗口归组、固定排列顺序，并在重启应用后保留分组。

## 运行截图

以下为实际运行截图。

### 左侧应用栏

<img src="docs/screenshots/sidebar-left.png" alt="Open Contexts 侧边栏按自定义分组列出 Mac 窗口" width="188">

左侧和右侧应用栏沿屏幕边缘居中排列。

### 底部应用栏

![Open Contexts 底部应用栏显示窗口图标与标题](docs/screenshots/sidebar-bottom.png)

底部应用栏从左向右排列并整体居中。空间不足时，每个窗口项会平均缩小，以便在一行内显示全部窗口。

### 窗口切换器

<img src="docs/screenshots/window-switcher.png" alt="Open Contexts 键盘窗口切换器列出单个 Mac 窗口" width="600">

窗口切换器按最近使用顺序展示窗口，可用键盘继续选择并切换。

## Mac 窗口切换器功能

| 功能 | 使用方式 |
| --- | --- |
| 窗口级切换 | 以窗口而不是应用为单位展示和切换，并跟踪最近使用顺序（MRU） |
| 屏幕边缘应用栏 | 支持左侧、右侧或底部，始终显示或移到屏幕边缘时唤出；可选择仅显示图标或同时显示标题 |
| 键盘切换器 | 默认 `⌘Tab` 切换所有窗口，`Command + 反引号` 切换当前应用窗口，可在设置中自定义；支持 Shift 反向切换、方向键、`Esc` 与松开快捷键修饰键确认 |
| 窗口搜索 | 按应用名或窗口标题搜索：按住切换器修饰键输入，松开即可切换；匹配文字黄色高亮 |
| 窗口激活 | 激活最小化或隐藏的窗口时尝试恢复显示 |
| 窗口信息 | 显示应用图标、窗口标题与系统可读取的 Dock 通知角标 |
| macOS 原生应用 | 使用 Swift、AppKit 和 SwiftUI 构建；应用更新使用 Sparkle |

### 保存自定义窗口分组

在侧边栏中将相关窗口放在一起，即使它们来自不同应用：

- 创建、重命名和删除分组，拖动窗口或分组调整顺序。
- 右键窗口选择“固定”，可将窗口固定在当前分组的位置，自动更新不会改变其位置；手动拖动仍可调整。
- 重启后恢复分组名称和顺序，以及可匹配窗口的分组、顺序和侧栏位置。

保存分组用于整理窗口列表，不会重新打开应用，也不会恢复桌面窗口的尺寸和位置。

### 寻找 Contexts 或 AltTab 的替代工具？

Open Contexts 复刻了 [Contexts](https://contexts.co/) 的应用栏和窗口切换体验，并加入可保存的自定义窗口分组。如果你需要免费开源的工具、紧凑的窗口标题列表和常驻侧边栏，可以考虑使用它。

Open Contexts 目前不支持触控板切换手势。全屏行为仍需在更多真实环境中验证。可阅读 [Mac 窗口切换器对比](https://opencontexts.zshnb.com/zh/compare/)，按自己的工作方式选择工具。

## 在 macOS 上下载与安装

系统要求：macOS 13 或更高版本。macOS 13 等较旧版本尚未完成实机验证。

1. 从[最新版本](https://github.com/zshnb/open-contexts/releases/latest)下载 Universal DMG。
2. 打开 DMG，将 `OpenContexts.app` 拖入“应用程序”文件夹，然后从该文件夹启动应用。
3. Open Contexts 启动后常驻菜单栏，不显示 Dock 图标或主窗口。点击菜单栏中的 Open Contexts 图标，选择“设置…”或“授予辅助功能权限…”。
4. 按照提示前往“系统设置 → 隐私与安全性 → 辅助功能”，授权 Open Contexts；如果授权后功能没有立即生效，请退出并重新启动应用。

辅助功能权限用于发现和切换窗口，以及接管快捷键。未授权或应用退出时，Open Contexts 不会接管 `⌘Tab`。应用更新后如果权限失效，请在辅助功能列表中移除 Open Contexts，再重新添加并授权。

以后可随时点击菜单栏图标打开“设置…”，或选择“退出 OpenContexts”结束运行。

安装了带更新功能的版本后，可从菜单栏选择“检查更新…”并在应用内安装新版本。已发布的 v0.2.1 不含更新器，需手动安装首个带 Sparkle 的 v0.3.0，此后才可在应用内升级。

### macOS 提示应用无法打开

未经 Developer ID 签名和 Apple 公证的构建可能被 Gatekeeper 拦截。确认安装包来自本仓库后，在终端执行：

```sh
xattr -dr com.apple.quarantine "/Applications/OpenContexts.app"
```

## 使用

- `⌘Tab`：打开所有窗口切换器；继续按 `Tab` 或按 `↓` 向前选择，按 `⇧Tab` 或 `↑` 向后选择。
- `Command + 反引号`：打开当前应用的窗口切换器。
- 搜索：打开切换器，按住修饰键输入应用名或窗口标题，松开即可切换。忽略大小写，匹配连续文本，支持空格组合搜索，如 `chr context`。`Backspace` 删除字符，删空后恢复窗口列表；无匹配时只关闭切换器。输入支持英文字母、数字和符号（可打印 ASCII），不支持中文或拼音。
- `Esc`：取消切换；松开快捷键中的任一修饰键，激活选中的窗口（默认松开 `⌘`）。
- 自定义快捷键：在设置中点击相应快捷键，再按下 Command、Option 或 Control 与按键的组合。Shift 保留用于反向切换，Esc 取消录入。修改立即生效，重启后保留；点击“恢复默认”可恢复 `⌘Tab` 和 `Command + 反引号`。
- 应用栏中的 `＋`：新建分组。
- 右键分组标题：重命名或删除分组。
- 拖动窗口：移入分组或调整顺序；拖动分组标题：调整分组顺序。
- 菜单栏设置：选择应用栏位于左侧、右侧或底部，以及始终显示或靠近屏幕边缘时显示。
- 显示内容：选择仅显示应用图标，或显示图标和窗口标题。底部栏空间不足时会平均缩小窗口项，在一行内显示全部窗口而不滚动。

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

推送 `v*` 标签后，GitHub Actions 会构建 Universal DMG，并将 DMG、`SHA256SUMS.txt`、含有 DMG EdDSA 签名的 `appcast.xml` 和与 DMG 同名的 Markdown 更新说明发布到 GitHub Releases。说明从 `CHANGELOG.md` 的当前版本提取，检测到新版本时显示在 Sparkle 更新窗口中。应用通过固定地址 `https://github.com/zshnb/open-contexts/releases/latest/download/appcast.xml` 检查更新。流水线校验说明链接、上传全部产物后，再公开发布。

Developer ID 模式默认启用签名与 Apple 公证，需要配置 `APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID` 和 `APPLE_APP_SPECIFIC_PASSWORD`。固定自签名模式使用同一份名为 `OpenContexts Release Signing` 的证书签署所有版本：将包含私钥的 P12 文件以 Base64 编码存入 GitHub Actions Secret `OPENCONTEXTS_CERTIFICATE_P12_BASE64`，将导出密码存入 `OPENCONTEXTS_CERTIFICATE_PASSWORD`，并将仓库变量 `RELEASE_SIGNING_MODE` 设为 `self-signed`。本地可用 `SIGNING_MODE=self-signed CODE_SIGN_IDENTITY=<证书 SHA-1> ./scripts/build-app.sh release` 构建。请安全备份这份证书与私钥；更换证书会改变应用代码身份，可能再次要求辅助功能授权。

三种模式都必须配置 GitHub Actions Secret `SPARKLE_ED_PRIVATE_KEY`，其私钥须与 `config/sparkle-public-key.txt` 中的公钥配对。当前发布校验只支持 Sparkle `generate_keys` 新格式导出的 Base64 编码 32 字节 seed，不支持旧版 96 字节密钥。缺少所需凭据时流水线会停止，不会自动降级签名。发布前需递增 `VERSION`。

没有 Apple 发布凭据时，可将仓库变量 `RELEASE_SIGNING_MODE` 设为 `self-signed`。此模式仍生成 EdDSA 签名更新，但未经 Apple 公证，Gatekeeper 可能阻止打开；从旧版 ad-hoc 签名切换到固定证书时，辅助功能权限可能需要重新授予一次。后续版本只要继续使用同一证书、应用标识和安装路径，代码身份即可保持稳定。Apple 不建议用自签名证书公开分发应用。设为 `adhoc` 可用于内部测试，但每次更新都可能重新授权；删除变量或设为 `developer-id` 可恢复 Developer ID 发布流程。

</details>

## 许可证

本项目采用 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)。允许在遵守许可证条款的前提下商业使用、修改和分发。
