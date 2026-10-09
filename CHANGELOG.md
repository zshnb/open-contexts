# Changelog

## [Unreleased]

## [0.3.10] - 2026-10-09

### Added

- Add “Close Window” to the window context menu, separate from “Quit App”, and respect the app's normal close confirmation. Disable the action when the window has no available close button.

### Changed

- Manual window dragging follows the chosen drop position and shifts other pinned windows to match. Automatic refreshes continue to preserve the saved pinned positions.

### Fixed

- Dropping a window on a group header inserts it at the start of the group, preventing the preview from jumping between positions while the pointer stays still.

### 新增

- 窗口右键菜单新增“关闭窗口”，与“退出应用”分开，并遵循应用原有的关闭确认流程；窗口没有可用关闭按钮时，该选项灰显。

### 调整

- 手动拖动窗口时按指定落点排序，其他固定窗口随新顺序顺延；自动刷新继续保持已保存的固定位置。

### 修复

- 拖动窗口到分组标题时插入组首，避免鼠标停在同一位置时预览反复跳动。

## [0.3.9] - 2026-10-09

### Added

- Read the current version's English and Chinese release notes in the update window before installing an update.

### Fixed

- Switching to a Finder window from the sidebar, window menu, or keyboard switcher no longer brings another Finder window to the front with it.

### 新增

- 检测到新版本时，可在更新窗口中查看本次版本的中英文更新说明，再选择安装。

### 修复

- 修复通过侧边栏、窗口菜单或快捷键切换 Finder 窗口时，另一个 Finder 窗口也被同时带到前台的问题。

## [0.3.7] - 2026-10-05

### Added

- Customize the all-windows and current-app window switching shortcuts in Settings. Changes take effect immediately and persist after restarting; recording supports cancellation, invalid or duplicate shortcut feedback, and restoring defaults. Shift switches backward, and releasing a shortcut modifier confirms the selected window.
- Read the new English and Chinese Mac window switching guides on the website, with a table of contents, method comparison, and direct language switching.

### Changed

- Remove the unsigned-app FAQ and its structured data from both website homepages.

### 新增

- 可在设置中自定义所有窗口与当前应用窗口的切换快捷键，修改立即生效并在重启后保留；录入支持取消、无效或重复组合键提示及恢复默认。Shift 反向切换，松开快捷键修饰键确认所选窗口。
- 官网新增中英文 Mac 窗口切换指南，包含目录、方式对比与直接语言切换。

### 调整

- 从中英文官网首页删除未签名应用的 FAQ 及对应结构化数据。

## [0.3.6] - 2026-09-29

### Fixed

- Fix the packaged app's startup crash by loading localization resources from the app bundle's `Contents/Resources` directory.

### 修复

- 从应用包的 `Contents/Resources` 目录加载本地化资源，修复打包版本启动时崩溃的问题。

## [0.3.5] - 2026-09-29

### Added

- Choose English, Spanish, French, Japanese, or Chinese in Settings, or follow the system language by default. App menus, sidebar, dialogs, and other interface text update with the selected language.

### 新增

- 可在设置中选择英语、西班牙语、法语、日语或中文，默认跟随系统语言。应用菜单、侧栏、弹窗等界面文案会随所选语言更新。

## [0.3.4] - 2026-09-28

### Fixed

- Restore pinned windows by stable app ID when their titles change, only when the app has one live window and one pinned record across all groups. Preserve existing bindings and avoid conflicting document URL matches.
- Keep active and pinned records when deduplicating same-name windows, so they do not move to Ungrouped.

### 修复

- 固定窗口标题变化后，改按稳定的应用 ID 恢复；仅在该应用当前只有一个窗口且所有分组中只有一条固定记录时恢复，并保留已有绑定、避开文档 URL 冲突。
- 同名窗口去重时保留活跃及固定记录，避免窗口被移到未分组。

## [0.3.3] - 2026-09-28

### Added

- The window context menu now supports pinning and unpinning a window, saving its position in the current group. Manual dragging can still change that position.

### Fixed

- Within each group, window records are deduplicated by `appID` and `title`; a newer record replaces the older one.

### 新增

- 窗口右键菜单支持「固定」和取消固定，固定后保存窗口在当前分组的位置；手动拖动仍可调整。

### 修复

- 同一分组内按 `appID` 和 `title` 去重，新窗口记录替换旧记录。

## [0.3.2] - 2026-09-28

### Fixed

- Keep the order of windows in the sidebar stable when focus changes, so windows without saved positions do not move with the most recently used order.
- Keyboard selection and mouse hover in the window switcher now highlight only one window; moving the mouse or continuing to use the shortcut selects the corresponding window.

### 修复

- 切换窗口焦点时保持侧栏窗口顺序稳定，避免未保存位置的窗口随最近使用顺序移动。
- 窗口切换器中的键盘选择和鼠标悬停只高亮一个窗口；移动鼠标或继续按快捷键时切换到对应选择。

## [0.3.1] - 2026-09-24

### Fixed

- Reassociate windows with their groups using saved matching identifiers when runtime window IDs change or the initial scan is empty. Duplicate matching keys within one custom group can be restored, while ambiguous matches across groups remain ungrouped. Refreshes during a run do not write to `groups.json`.

### 修复

- 窗口运行时 ID 变化或首次扫描为空后，按已保存的匹配标识重新关联分组；同一自定义组内的重复匹配键可恢复，跨组歧义仍保持未分组。运行中的刷新不会写入 `groups.json`。

## [0.3.0] - 2026-09-24

### Added

- Check for updates from the menu bar, then download and install them in the app. Release packages include a Sparkle appcast with an EdDSA signature for the DMG.

### Changed

- Restore saved window groups on the first successful scan. Later periodic refreshes only sync live window information and no longer read or rewrite group records.

### 新增

- 菜单栏支持检查更新，并在应用内下载和安装；发布包附带包含 DMG EdDSA 签名的 Sparkle appcast。

### 改进

- 首次成功扫描时恢复已保存的窗口分组；后续定时刷新只同步实时窗口信息，不再读取或改写分组记录。

## [0.2.1] - 2026-09-23

### Fixed

- Restore the context menu for window icons in the sidebar, allowing users to switch among windows of the same app, hide the app, or quit it.

### Documentation

- Show the app icon and unobstructed screenshots in the README, and add installation and Accessibility permission instructions.

### 修复

- 恢复应用栏窗口图标的右键菜单，可切换同一应用的窗口、隐藏应用或退出应用。

### 文档

- README 展示软件图标和无遮挡截图，并补充安装与辅助功能授权说明。

## [0.2.0] - 2026-09-23

### Added

- Place the sidebar at the bottom of the screen and choose between icons only or icons with window titles. These settings are saved.

### Changed

- Lay out the bottom bar from left to right, evenly shrinking window items when space is limited while keeping one line without scrolling.
- Center the bottom bar horizontally by default, and support horizontal drag reordering and hover display.

### 新增

- 应用栏支持放置在屏幕底部，并可选择仅显示图标或同时显示图标和窗口标题；设置会持久保存。

### 改进

- 底部应用栏从左到右排列，空间不足时均匀缩减窗口项宽度并保持单行无滚动。
- 底部应用栏默认水平居中，并适配横向拖拽排序与悬浮显示。

## [0.1.1] - 2026-09-22

### Fixed

- Save and restore the group and order of windows without titles or document URLs using the app identity, while avoiding ambiguous matches across apps, windows with titles, or multiple windows of the same app.
- Filter ordinary dialogs that have no title or document URL and are clearly nonmodal, so auxiliary windows from apps such as CapCut are not shown twice.
- Use the stacked-window template icon in the menu bar at a consistent 18 pt size, and add an Accessibility name.

### Changed

- Limit title width in the sidebar and window switcher, truncating long titles at the end within the panels.

### 修复

- 按应用身份保存并恢复无标题、无文档窗口的分组与顺序，同时避免跨应用、有标题或同应用多窗口时的歧义匹配。
- 过滤无标题、无文档且明确非模态的普通对话框，避免 CapCut 等应用的辅助窗口重复显示。
- 菜单栏改用层叠窗口模板图标，统一为 18pt，并补充辅助功能名称。

### 改进

- 限制侧栏和窗口切换器中的标题宽度，超长标题在面板范围内从尾部截断。

## [0.1.0] - 2026-09-22

### Added

- Provide a compact macOS window sidebar with window grouping, sorting, and saved positions.
- Use Command-Tab to switch among all windows and Command-backtick to switch among windows of the current app.
- Support left and right sidebar positions, drag-and-drop window grouping, and live order previews.
- Display app notification badges from the system Dock.

### 新增

- 提供紧凑的 macOS 窗口侧栏，支持窗口分组、排序与位置保存。
- 使用 Command-Tab 切换全部窗口，使用 Command-反引号切换当前应用窗口。
- 支持左、右侧栏位置，以及窗口拖放分组和实时排序预览。
- 同步显示系统 Dock 提供的应用通知角标。
