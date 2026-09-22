# 首版实现与验收记录

## 范围

以 `requirements.md` 和两个 accepted ADR 为依据。首版采用 Swift Package 管理源码与测试，本地脚本生成 `.app`，不增加第三方依赖或发布基础设施。

已实现的模块：

- `OpenContextsCore`：窗口描述、分组管理、顺序与身份恢复、原子持久化、损坏文件保护。
- `WindowService`：后台串行 AX 窗口扫描、运行期稳定标识、MRU、恢复隐藏／最小化窗口、当前显示器全屏检测。
- `ShortcutController`：Command 快捷键事件过滤、前后选择、取消与松键提交、权限及会话失效回退。
- `Panels` / `AppController`：多屏侧栏与切换器、拖放、分组管理、悬浮显示、菜单栏生命周期。
- `SettingsView`：SwiftUI 设置、两种窗口快捷键录制与冲突检查。

窗口扫描采用 0.4 秒轮询，并使用后台串行队列及 AX 超时，避免阻塞键盘事件回调。非常短暂的焦点切换可能不进入 MRU；若实际使用中出现遗漏，再引入 AXObserver。窗口所属应用不提供 Accessibility 窗口时，本工具无法补出其窗口。

## 已执行验证（2026-09-21）

| 检查 | 结果 |
| --- | --- |
| `swift test` | 12 项测试通过，0 失败（6 项分组、2 项悬浮状态、3 项窗口资格、1 项显示标题） |
| `./scripts/build-app.sh` | Release 构建通过，生成 `dist/OpenContexts.app` |
| `OpenContexts --self-check` | 退出码 0；快捷键状态、设置值校验及录制生命周期检查通过 |
| `OpenContexts --ui-self-check` | Release 包退出码 0；覆盖左右、0/1/3/200 窗口内容高度、溢出滚动到底、多变少收缩、24px 行与零间距，以及鼠标坐标重放下的悬浮／刷新／离开／重进／拖拽 |
| `OpenContexts --window-self-check` | Release 包退出码 0；本地设置窗口无需 AX 登记、重复登记去重、移除／重登记、移除后的扫描结果合并通过 |
| `codesign --verify --strict` | 本地 ad-hoc 签名有效 |
| `plutil -lint` | 应用 Info.plist 合法 |
| GUI 启动 | 已实际启动本轮 Release 应用，确认设置可见且位置仅左右；辅助功能状态为未授权，第三方窗口列表待实机复核 |
| TCC 授权 / 真实按键完整验收 | 未执行 |
| Contexts 3.9.0 视觉对照 | 截图失败，未验收 |

六项核心测试覆盖分组与窗口排序／删除、文档身份恢复与关闭位置保留、两侧身份歧义、标题变化及跨应用隔离、损坏数据保护、重复窗口输入及未变化列表的免写入处理。自检不会安装键盘拦截或请求权限。

## 启动崩溃修复（2026-09-21）

用户实际启动时发现 `NSPanel` 子类调用带 `screen:` 的 `NSWindow` 初始化器，引发未实现初始化器的 Swift trap。侧栏与切换器均改用四参数 designated initializer；显示器定位仍由各自布局方法负责。增加 GUI 冒烟测试后，重新验证 Release 构建、两类自检及六项核心测试均通过，并实际打开应用确认设置窗口可见。

## 实机验收步骤

上一版界面更新（2026-09-21）：曾实际启动应用并逐一检查四边位置。随后根据用户反馈将位置收敛为左右，并将侧栏改为按内容高度收缩。图标为 24px；应用栏已进一步改为 24px 行高、0 垂直间距，切换器保留 32px 行高和浅蓝背景。

左右／内容高度更新已通过 Release 构建、两类自检和八项测试。侧栏按组头、窗口行、操作区及间距计算自然高度，屏幕可用高度为上限；条目减少后会收缩，并沿屏边垂直居中。旧版上下位置自动迁移为右侧，设置自检覆盖迁移及左侧持久化。

无标题条目修复：早期按 ChatGPT bundle identifier 排除无标题窗口的策略遗漏了 Chrome 同类现象，已改为检查普通窗口能力的通用策略。真实无标题窗口回退显示应用名，原始标题仍用于分组身份匹配。输入辅助窗口的实际 AX 属性尚待实机复核，不以策略测试代替真实打字场景验收。OpenContexts 设置通过本地窗口登记纳入列表，侧栏和切换面板仍排除。

悬浮回缩修复：移除随窗口尺寸变化而重建的 NSTrackingArea，避免伸缩触发 mouseExited 反馈。用屏幕坐标与固定展开区域判断，真实离开 120ms 后收起，重进取消收起，拖拽保持展开；重复列表刷新不重置窗口尺寸。最新 Release 包及全部自检已通过并实际启动，因重新签名后辅助功能未授权，真实 ChatGPT 列表仍待授权后复核。

以下项目必须在用户授予辅助功能权限后验证。自动测试不能证明系统窗口管理、权限、键盘拦截或视觉效果正确。

1. **无权限与退出回退**：未授权启动，检查权限提示，Command-Tab 仍打开系统切换器；授权后可接管；运行中撤销权限、退出应用后再次检查系统切换器。
2. **窗口粒度**：同一应用打开两个不同窗口，创建两个分组，分别拖入并调整顺序。点击每个条目应激活正确窗口；关闭窗口后条目消失，空分组仍显示；无窗口应用和纯菜单栏应用不显示。打开网易云，确认真实无标题窗口显示应用名；在 Chrome、ChatGPT 中持续输入并切换输入法，确认辅助窗口不闪入列表且正常窗口保留。打开、关闭并重开 OpenContexts 设置，确认对应条目出现、消失且不重复，点击能激活设置。
3. **分组管理**：重命名、拖动分组；删除含窗口的分组后，窗口应进入「未分组」。重启工具验证分组名称、顺序及空组保留。
4. **恢复身份**：重开具有唯一文档 URL 或标题的窗口应恢复位置；多个同应用同名且无文档 URL 的窗口应留在「未分组」；运行中改标题应留在原组。
5. **键盘**：Command-Tab 前进、Shift-Tab 后退、Up/Down 移动、Escape 取消、松 Command 激活。检查最近使用顺序；两种自定义快捷键分别列出所有窗口和当前应用窗口；配置冲突应被拒绝。
6. **隐藏／最小化**：隐藏应用、最小化窗口，确认仍列出；选中后应恢复并激活正确窗口。
7. **桌面空间／全屏**：将窗口移到其他 Space，另开全屏窗口，确认切换器仍列出且可切换；全屏侧栏无论常显设置如何都收至边缘，悬浮能唤出。
8. **多显示器**：每屏都有相同窗口侧栏；切换器在每屏中心同时出现，列表与选择同步；拔插显示器后没有残留面板。验证主屏与副屏分别全屏的侧栏行为。
9. **侧栏显示**：常显模式保持展开，悬浮模式离开收起、进入边缘展开；拖拽过程中不意外收起或丢失目标。
10. **视觉**：捕获本机 Contexts 3.9.0 侧栏和切换器，对照字体、尺寸、颜色、间距、选中态与交互。当前截图工具返回 `The screen capture failed`，本项尚未执行。

## 系统 API 依据

- [AXWindows](https://developer.apple.com/documentation/applicationservices/kaxwindowsattribute)：获取应用暴露的窗口。
- [AXMinimized](https://developer.apple.com/documentation/applicationservices/kaxminimizedattribute)：读取或恢复最小化状态。
- [CGEventTapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)) 与 [tapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:))：安装与恢复键盘事件过滤。

第三方应用的 Accessibility 实现和系统策略会影响跨 Space、全屏及激活结果。这些行为需要以上实机步骤验证，不以编译成功替代。
