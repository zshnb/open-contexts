import AppKit
import ApplicationServices
import Combine
import OpenContextsCore
import OSLog

@MainActor
final class WindowService: ObservableObject {
    @Published private(set) var windows: [WindowInfo] = []
    @Published private(set) var appBadges: [String: String] = [:]
    @Published private(set) var hasAccessibility = false
    @Published private(set) var fullscreenScreenIDs: Set<UInt32> = []

    var focusedWindowID: String? { focusedID }

    private final class WeakWindow {
        weak var value: NSWindow?
        init(_ value: NSWindow) { self.value = value }
    }

    private struct TrackedWindow: @unchecked Sendable {
        let id: String
        let element: AXUIElement
        var info: WindowInfo
    }

    private struct ApplicationSnapshot: Sendable {
        let processID: pid_t
        let appID: String
        let appName: String
    }

    private struct ScanResult: @unchecked Sendable {
        let windows: [TrackedWindow]
        let focusedID: String?
        let fullscreenScreenIDs: Set<UInt32>
        let activeAppIDs: Set<String>
        let badgeReads: [String: DockBadgeRead]?
    }

    private enum AttributeRead<Value> {
        case value(Value)
        case noValue
        case failure(AXError)
    }

    private enum CapabilityProbe {
        case value(WindowTaskCapability)
        case invalidElement
    }

    private let logger = Logger(subsystem: "OpenContexts", category: "windows")
    private var tracked: [TrackedWindow] = []
    private var localWindows: [String: WeakWindow] = [:]
    private var externalFocusedID: String?
    private var focusedID: String?
    private var timer: Timer?
    private var scanInFlight = false
    private var lastBadgeScanAt = -Double.infinity
    private var badgeState = DockBadgeState()
    private let scanQueue = DispatchQueue(label: "OpenContexts.WindowScan", qos: .userInitiated)

    func start() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        hasAccessibility = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        refresh()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        hasAccessibility = trusted
        guard trusted else {
            tracked = []
            externalFocusedID = nil
            fullscreenScreenIDs = []
            publishWindows()
            return
        }
        guard !scanInFlight else { return }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let applications = NSWorkspace.shared.runningApplications.compactMap { application -> ApplicationSnapshot? in
            guard application.activationPolicy == .regular, application.processIdentifier != ownPID else { return nil }
            let appID = application.bundleIdentifier
                ?? application.bundleURL?.path
                ?? "pid:\(application.processIdentifier)"
            return ApplicationSnapshot(
                processID: application.processIdentifier,
                appID: appID,
                appName: application.localizedName ?? appID
            )
        }
        let now = ProcessInfo.processInfo.systemUptime
        let scanBadges = now - lastBadgeScanAt >= 2
        if scanBadges { lastBadgeScanAt = now }
        let dockPID = scanBadges
            ? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            : nil
        let previous = tracked
        scanInFlight = true
        scanQueue.async { [weak self] in
            let result = Self.scan(applications: applications, previous: previous,
                                   frontmostPID: frontmostPID,
                                   badgeReads: scanBadges ? dockPID.flatMap(Self.scanDockBadges) : nil)
            Task { @MainActor [weak self] in self?.apply(result) }
        }
    }

    private func apply(_ result: ScanResult) {
        scanInFlight = false
        guard AXIsProcessTrusted() else {
            hasAccessibility = false
            tracked = []
            externalFocusedID = nil
            fullscreenScreenIDs = []
            publishWindows()
            return
        }

        let discoveredIDs = Set(result.windows.map(\.id))
        var orderedIDs = tracked.map(\.id).filter(discoveredIDs.contains)
        orderedIDs.append(contentsOf: result.windows.map(\.id).filter { !orderedIDs.contains($0) })

        externalFocusedID = result.focusedID
        if let externalFocusedID, let index = orderedIDs.firstIndex(of: externalFocusedID), index != 0 {
            orderedIDs.remove(at: index)
            orderedIDs.insert(externalFocusedID, at: 0)
        }

        let byID = Dictionary(uniqueKeysWithValues: result.windows.map { ($0.id, $0) })
        tracked = orderedIDs.compactMap { byID[$0] }
        fullscreenScreenIDs = result.fullscreenScreenIDs
        badgeState.merge(activeAppIDs: result.activeAppIDs, reads: result.badgeReads)
        if appBadges != badgeState.badges { appBadges = badgeState.badges }
        publishWindows()
    }

    func activate(_ id: String) {
        if let window = localWindows[id]?.value {
            if window.isMiniaturized { window.deminiaturize(nil) }
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            publishWindows()
            return
        }
        guard hasAccessibility, let window = tracked.first(where: { $0.id == id }) else { return }

        if let application = NSRunningApplication(processIdentifier: window.info.processID) {
            if application.isHidden { application.unhide() }
            application.activate(options: [.activateIgnoringOtherApps])
        }

        scanQueue.async { [weak self] in
            let appElement = AXUIElementCreateApplication(window.info.processID)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            AXUIElementSetMessagingTimeout(window.element, 0.2)
            if Self.boolAttribute(kAXMinimizedAttribute, of: window.element) {
                AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window.element)
            let result = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            if result != .success {
                self?.logger.error("Failed to raise window \(id, privacy: .public): AX error \(result.rawValue)")
            }
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func registerLocalWindow(_ window: NSWindow, id: String) {
        localWindows[id] = WeakWindow(window)
        publishWindows()
    }

    func unregisterLocalWindow(id: String) {
        localWindows.removeValue(forKey: id)
        publishWindows()
    }

    static func selfCheck() -> Bool {
        _ = NSApplication.shared
        let service = WindowService()
        let id = "local:self-check"
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        service.registerLocalWindow(window, id: id)
        guard service.windows.map(\.id) == [id] else { return false }
        service.registerLocalWindow(window, id: id)
        guard service.windows.filter({ $0.id == id }).count == 1 else { return false }
        service.unregisterLocalWindow(id: id)
        service.apply(ScanResult(windows: [], focusedID: nil, fullscreenScreenIDs: [],
                                 activeAppIDs: [], badgeReads: nil))
        guard !service.windows.contains(where: { $0.id == id }) else { return false }
        service.registerLocalWindow(window, id: id)
        guard service.windows.filter({ $0.id == id }).count == 1,
              AXIsProcessTrusted(),
              let dockPID = NSRunningApplication.runningApplications(
                  withBundleIdentifier: "com.apple.dock"
              ).first?.processIdentifier,
              let reads = scanDockBadges(processID: dockPID), !reads.isEmpty else { return false }
        let readable = reads.values.filter {
            if case .value = $0 { return true }
            return false
        }.count
        let badged = reads.values.filter {
            if case let .value(raw) = $0 { return DockBadgeState.displayValue(raw) != nil }
            return false
        }.count
        FileHandle.standardError.write(Data(
            "Dock badge self-check: mapped=\(reads.count) readable=\(readable) badged=\(badged)\n".utf8
        ))
        return true
    }

    private func publishWindows() {
        localWindows = localWindows.filter { $0.value.value != nil }
        let localInfos = localWindows.compactMap { id, reference -> WindowInfo? in
            guard let window = reference.value else { return nil }
            let appID = Bundle.main.bundleIdentifier ?? "OpenContexts"
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? "OpenContexts"
            return WindowInfo(id: id, appID: appID, appName: appName, title: window.title,
                              processID: ProcessInfo.processInfo.processIdentifier)
        }
        let allInfos = tracked.map(\.info) + localInfos
        let byID = Dictionary(uniqueKeysWithValues: allInfos.map { ($0.id, $0) })
        var orderedIDs = windows.map(\.id).filter { byID[$0] != nil }
        orderedIDs.append(contentsOf: allInfos.map(\.id).filter { !orderedIDs.contains($0) })
        let localFocusedID = NSApp.isActive
            ? localWindows.first { $0.value.value?.isKeyWindow == true }?.key
            : nil
        focusedID = localFocusedID ?? externalFocusedID
        if let focusedID, let index = orderedIDs.firstIndex(of: focusedID), index != 0 {
            orderedIDs.remove(at: index)
            orderedIDs.insert(focusedID, at: 0)
        }
        windows = orderedIDs.compactMap { byID[$0] }
    }

    nonisolated private static func scan(
        applications: [ApplicationSnapshot],
        previous: [TrackedWindow],
        frontmostPID: pid_t?,
        badgeReads: [String: DockBadgeRead]?
    ) -> ScanResult {
        var discovered: [TrackedWindow] = []
        var focusedElement: AXUIElement?
        var usedIDs: Set<String> = []

        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processID)
            AXUIElementSetMessagingTimeout(appElement, 0.2)
            let appWindowsRead: AttributeRead<[AXUIElement]> = readAttribute(kAXWindowsAttribute, of: appElement)
            let appWindows: [AXUIElement]
            switch appWindowsRead {
            case let .value(windows):
                appWindows = windows
            case .failure(.invalidUIElement):
                appWindows = []
            case .noValue, .failure:
                discovered.append(contentsOf: previous.filter { $0.info.processID == application.processID })
                usedIDs.formUnion(previous.lazy.filter { $0.info.processID == application.processID }.map(\.id))
                continue
            }
            if application.processID == frontmostPID {
                focusedElement = attribute(kAXFocusedWindowAttribute, of: appElement)
            }

            for element in appWindows {
                AXUIElementSetMessagingTimeout(element, 0.2)
                guard !discovered.contains(where: { CFEqual($0.element, element) }) else { continue }

                // ponytail: linear identity matching is simpler and fast for desktop-sized window lists.
                let existing = previous.first { !usedIDs.contains($0.id) && CFEqual($0.element, element) }
                let roleState: WindowCandidateState
                let roleRead: AttributeRead<String> = readAttribute(kAXRoleAttribute, of: element)
                switch roleRead {
                case let .value(role):
                    if role == kAXWindowRole {
                        let subroleRead: AttributeRead<String> = readAttribute(kAXSubroleAttribute, of: element)
                        switch subroleRead {
                        case let .value(subrole): roleState = .attributes(role: role, subrole: subrole)
                        case .noValue: roleState = .attributes(role: role, subrole: nil)
                        case let .failure(error):
                            roleState = error == .invalidUIElement ? .notListed : .attributeReadFailed
                        }
                    } else {
                        roleState = .attributes(role: role, subrole: nil)
                    }
                case .noValue:
                    roleState = .missingRole
                case let .failure(error):
                    roleState = error == .invalidUIElement ? .notListed : .attributeReadFailed
                }

                let title: String
                let titleRead: AttributeRead<String> = readAttribute(kAXTitleAttribute, of: element)
                switch titleRead {
                case let .value(value):
                    title = value
                case .noValue:
                    title = ""
                case .failure(.invalidUIElement):
                    continue
                case .failure:
                    guard let existing else { continue }
                    title = existing.info.title
                }

                let document: String?
                let documentRead: AttributeRead<String> = readAttribute(kAXDocumentAttribute, of: element)
                switch documentRead {
                case let .value(value):
                    document = value
                case .failure(.invalidUIElement):
                    continue
                case .failure:
                    guard let existing else { continue }
                    document = existing.info.documentURL
                case .noValue:
                    let urlRead: AttributeRead<URL> = readAttribute(kAXURLAttribute, of: element)
                    switch urlRead {
                    case let .value(value):
                        document = value.absoluteString
                    case .noValue:
                        document = nil
                    case .failure(.invalidUIElement):
                        continue
                    case .failure:
                        guard let existing else { continue }
                        document = existing.info.documentURL
                    }
                }

                let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let hasDocument = document?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let isModal: Bool
                let modalStatusUnknown: Bool
                let modalRead: AttributeRead<Bool> = readAttribute(kAXModalAttribute, of: element)
                switch modalRead {
                case let .value(value):
                    isModal = value
                    modalStatusUnknown = false
                case .noValue:
                    isModal = false
                    modalStatusUnknown = roleState == .attributes(role: "AXWindow", subrole: "AXSystemDialog")
                case .failure(.invalidUIElement):
                    continue
                case .failure:
                    isModal = false
                    modalStatusUnknown = true
                }

                let taskCapability: WindowTaskCapability
                switch probeTaskCapability(of: element) {
                case let .value(value):
                    taskCapability = modalStatusUnknown && value == .unsupported ? .readFailed : value
                case .invalidElement:
                    continue
                }

                guard WindowEligibilityPolicy.shouldInclude(
                    roleState,
                    hasTitle: hasTitle,
                    hasDocument: hasDocument,
                    isModal: isModal,
                    modalStatusUnknown: modalStatusUnknown,
                    taskCapability: taskCapability,
                    previouslyTracked: existing != nil
                ) else { continue }

                let id = existing?.id ?? UUID().uuidString
                usedIDs.insert(id)
                discovered.append(TrackedWindow(
                    id: id,
                    element: element,
                    info: WindowInfo(
                        id: id,
                        appID: application.appID,
                        appName: application.appName,
                        title: title,
                        documentURL: document,
                        processID: application.processID
                    )
                ))
            }
        }

        let focusedID = focusedElement.flatMap { focused in
            discovered.first { CFEqual($0.element, focused) }?.id
        }
        return ScanResult(
            windows: discovered,
            focusedID: focusedID,
            fullscreenScreenIDs: fullscreenDisplays(in: discovered),
            activeAppIDs: Set(applications.map(\.appID)),
            badgeReads: badgeReads
        )
    }

    nonisolated private static func scanDockBadges(processID: pid_t) -> [String: DockBadgeRead]? {
        let dock = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(dock, 0.15)
        let rootChildren: AttributeRead<[AXUIElement]> = readAttribute(kAXChildrenAttribute, of: dock)
        guard case let .value(children) = rootChildren else { return nil }

        var pending = children.map { ($0, 0) }
        var reads: [String: DockBadgeRead] = [:]
        while let (element, depth) = pending.popLast() {
            AXUIElementSetMessagingTimeout(element, 0.15)
            let role: String? = attribute(kAXRoleAttribute, of: element)
            if role == "AXDockItem" {
                let urlRead: AttributeRead<URL> = readAttribute(kAXURLAttribute, of: element)
                guard case let .value(url) = urlRead,
                      let appID = DockBadgeState.appID(for: url) else { continue }
                let statusRead: AttributeRead<String> = readAttribute("AXStatusLabel", of: element)
                switch statusRead {
                case let .value(value): reads[appID] = .value(value)
                case .noValue: reads[appID] = .value(nil)
                case .failure: reads[appID] = .failure
                }
            } else if depth < 7 {
                let childrenRead: AttributeRead<[AXUIElement]> = readAttribute(kAXChildrenAttribute, of: element)
                if case let .value(children) = childrenRead {
                    pending.append(contentsOf: children.map { ($0, depth + 1) })
                }
            }
        }
        return reads
    }

    nonisolated private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        let read: AttributeRead<T> = readAttribute(name, of: element)
        guard case let .value(value) = read else { return nil }
        return value
    }

    nonisolated private static func readAttribute<T>(_ name: String, of element: AXUIElement) -> AttributeRead<T> {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if result == .attributeUnsupported || result == .noValue { return .noValue }
        guard result == .success else { return .failure(result) }
        guard let value else { return .noValue }
        guard let typed = value as? T else { return .noValue }
        return .value(typed)
    }

    nonisolated private static func boolAttribute(_ name: String, of element: AXUIElement) -> Bool {
        let value: CFTypeRef? = attribute(name, of: element)
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
    }

    nonisolated private static func probeTaskCapability(of element: AXUIElement) -> CapabilityProbe {
        var readFailed = false
        for attributeName in [kAXMainAttribute, kAXMinimizedAttribute] {
            var settable = DarwinBoolean(false)
            let result = AXUIElementIsAttributeSettable(element, attributeName as CFString, &settable)
            if result == .success, settable.boolValue { return .value(.supported) }
            if result == .invalidUIElement { return .invalidElement }
            if result != .success, result != .attributeUnsupported, result != .noValue { readFailed = true }
        }

        let mainRead: AttributeRead<Bool> = readAttribute(kAXMainAttribute, of: element)
        switch mainRead {
        case .value(true): return .value(.supported)
        case .failure(.invalidUIElement): return .invalidElement
        case .failure: readFailed = true
        case .value(false), .noValue: break
        }

        return .value(readFailed ? .readFailed : .unsupported)
    }

    nonisolated private static func fullscreenDisplays(in windows: [TrackedWindow]) -> Set<UInt32> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }

        let visibleFrames = onScreenWindowFrames()
        var result: Set<UInt32> = []
        for window in windows where boolAttribute("AXFullScreen", of: window.element) {
            guard let frame = frame(of: window.element),
                  visibleFrames[window.info.processID]?.contains(where: {
                      $0.intersection(frame).area >= frame.area * 0.9
                  }) == true else { continue }
            if let display = displays.max(by: {
                CGDisplayBounds($0).intersection(frame).area < CGDisplayBounds($1).intersection(frame).area
            }), CGDisplayBounds(display).intersection(frame).area > 0 {
                result.insert(display)
            }
        }
        return result
    }

    nonisolated private static func onScreenWindowFrames() -> [pid_t: [CGRect]] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var result: [pid_t: [CGRect]] = [:]
        for window in raw where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            result[owner, default: []].append(frame)
        }
        return result
    }

    nonisolated private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(kAXPositionAttribute, of: element),
              let size: AXValue = attribute(kAXSizeAttribute, of: element),
              AXValueGetType(position) == .cgPoint,
              AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
