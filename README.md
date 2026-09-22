# Open Contexts

按 [已确认需求](docs/requirements.md) 实现的个人用 macOS 窗口侧栏与窗口切换器。Swift + AppKit，设置页使用 SwiftUI；无第三方依赖。

## 构建与运行

需要 macOS 13 或更高版本及支持 Swift 5.9 的 Xcode Command Line Tools。当前验收环境是 Apple Silicon、macOS 27、Swift 6.4；较旧系统兼容性尚未实测。

```sh
swift test
./scripts/build-app.sh
dist/OpenContexts.app/Contents/MacOS/OpenContexts --self-check
dist/OpenContexts.app/Contents/MacOS/OpenContexts --ui-self-check
open dist/OpenContexts.app
```

打包脚本默认使用钥匙串中唯一的 `Apple Development` 证书签名；若有多个证书，需通过 `CODE_SIGN_IDENTITY` 指定证书 SHA-1 或完整名称。稳定的开发签名可避免正常重建后反复丢失辅助功能授权。没有开发证书时脚本会在构建和覆盖现有应用前退出；仅需临时自检时可用 `CODE_SIGN_IDENTITY=- ./scripts/build-app.sh` 生成 ad-hoc 签名应用。开发签名不是公证或对外发行包。请从稳定位置启动 `.app`，不要以 `swift run` 作为日常使用入口，以免辅助功能授权绑定到开发工具。

首次启动后，从菜单栏进入设置，按提示在「系统设置 → 隐私与安全性 → 辅助功能」授权 Open Contexts。授权需要用户在系统设置中完成。未获权限时不接管 Command-Tab；退出应用会移除快捷键拦截。测试时请先退出其他接管 Command-Tab 的工具，避免事件拦截冲突。

「所有窗口」固定使用 Command-Tab，「当前应用窗口」固定使用 Command-反引号。侧栏底部可新建分组；右键分组标题可重命名或删除。把窗口拖到分组标题会放到组末，拖到窗口行会插到其前面；分组拖到另一标题前排序，底部拖放区可移到末尾。

「侧栏位置」仅可选择左、右，重启后保留；旧版上、下位置回退到右侧。侧栏宽 188pt、窗口行高 25pt、图标 18pt，按内容高度收缩并沿屏幕边缘垂直居中，超出屏幕可用高度才滚动。仅远离屏幕的一侧使用圆角；收起时完全隐藏，移到屏幕边缘可唤出。窗口行保持图标和标题，拖动时实时预览排列，落下后保存。切换器宽度不超过 600pt、行高 28pt，采用灰白半透明背景，右侧对齐显示应用名、图标和标题，选中项为蓝色，不显示首字母列。正常无标题窗口回退显示系统提供的应用名；无标题、无文档且缺少普通窗口能力的辅助窗口不会加入列表，瞬时属性读取失败不会立刻移除已识别窗口。辅助窗口采用统一过滤规则，不按应用名称屏蔽。OpenContexts 设置打开时也会列入，关闭后移除。

`--ui-self-check` 需要已登录的图形会话，会短暂创建并关闭侧栏和切换器，检查真实 AppKit 初始化与布局；不会请求辅助功能权限或安装全局快捷键。

## 数据

分组与窗口期望位置保存在 `~/Library/Application Support/OpenContexts/groups.json`。以应用标识和文档 URL（优先）或标题作唯一匹配；不能唯一识别的窗口进入「未分组」。运行中窗口改标题不会重新分组。

## 验收

自动检查与需要权限的实机项目见 [验收记录](docs/implementation-status.md)。已按提供的参考图调整布局；多显示器/跨空间仍需实机验证。

设计依据：[术语](CONTEXT.md)、[技术栈 ADR](docs/adr/0001-native-macos-ui.md)、[窗口粒度 ADR](docs/adr/0002-window-granularity.md)。

## 发布

GitHub Actions 在推送 `v*` 标签时构建 Universal DMG，并把 DMG、`SHA256SUMS.txt` 和对应版本的更新日志发布到 GitHub Releases。发布前同时更新仓库根目录的 `VERSION` 和 `CHANGELOG.md`：`VERSION` 必须是无前导零的三段版本号，例如 `0.2.0`；更新日志标题必须写成 `## [0.2.0] - YYYY-MM-DD`，并至少包含一条非空列表项。可选的 `## [Unreleased]` 不会进入 Release 正文。先在本地验证元数据，并把版本、日志和代码改动提交后，再给该提交打完全对应的标签：

```sh
python3 -B scripts/test-release-notes.py
python3 -B scripts/release-notes.py --tag v0.2.0 --output dist/release-notes.md
git tag v0.2.0
git push origin v0.2.0
```

默认发布使用 Developer ID 签名和 Apple 公证。请在 GitHub Actions Secrets 中配置 `APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD`。证书内容是含私钥的 Developer ID Application `.p12` 文件经 base64 编码后的文本；流水线要求其中恰好有一个 Developer ID Application 身份，缺少凭据时会停止发布，不会降级签名。

确需内部测试包时，可把仓库变量 `RELEASE_SIGNING_MODE` 明确设为 `adhoc`。这种产物未经 Apple 公证，Release 正文会显示 Gatekeeper 提示。删除该变量或设为 `developer-id` 即恢复正式发布。日常本地构建仍使用钥匙串中的 Apple Development 证书。

首次正式发布前需配置上述 Secrets；仅发布内部测试包时，需显式把仓库变量 `RELEASE_SIGNING_MODE` 设为 `adhoc`。流水线使用 GitHub 托管的 Apple Silicon `macos-15` runner；应用声明最低 macOS 13，但较旧系统兼容性仍需实机验证。

发布阶段先创建草稿并上传附件，最后才公开。失败后可直接重新运行同一工作流以恢复已有草稿；已经公开的同版本 Release 不会被覆盖。
