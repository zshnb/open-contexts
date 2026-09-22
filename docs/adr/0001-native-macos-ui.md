# ADR 0001：原生 macOS UI 技术栈

## 决定

采用 Swift + AppKit 实现窗口侧栏和窗口切换器面板；设置界面使用 SwiftUI。跨应用窗口发现与激活使用 Accessibility 等系统 API。

## 原因

AppKit 适合管理本应用的 macOS 面板与悬浮界面；SwiftUI 适合设置页。跨应用控制不是 AppKit 能力，需通过系统 API 实测权限、空间和全屏行为。相比 Objective-C 可减少新代码维护成本；相比纯 SwiftUI 可避免为面板管理建立额外桥接层。

## 结果

UI 验收目标是忠实复刻 Contexts 3.9.0 的界面与交互，不是改用新的 macOS 视觉风格。
