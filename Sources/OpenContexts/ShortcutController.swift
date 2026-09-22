@preconcurrency import ApplicationServices
import AppKit
import Combine

enum SwitcherAction: Equatable {
    case begin(currentAppOnly: Bool, reverse: Bool)
    case step(Int)
    case commit
    case cancel
}

private struct ShortcutState {
    private(set) var isSwitching = false

    mutating func begin(currentAppOnly: Bool, reverse: Bool, allowed: Bool) -> SwitcherAction? {
        guard !isSwitching, allowed else { return nil }
        isSwitching = true
        return .begin(currentAppOnly: currentAppOnly, reverse: reverse)
    }

    mutating func step(_ amount: Int) -> SwitcherAction? {
        isSwitching ? .step(amount) : nil
    }

    mutating func finish(commit: Bool) -> SwitcherAction? {
        guard isSwitching else { return nil }
        isSwitching = false
        return commit ? .commit : .cancel
    }
}

@MainActor
final class ShortcutController: ObservableObject {
    static let allWindowsKeyCode: UInt16 = 48
    static let currentAppKeyCode: UInt16 = 50

    @Published private(set) var isRunning = false
    var onAction: ((SwitcherAction) -> Void)?
    var canBegin: ((Bool) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var state = ShortcutState()

    func start() -> Bool {
        if eventTap != nil { return isRunning }
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: shortcutEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        observeSessionChanges()
        return true
    }

    func stop() {
        if let action = state.finish(commit: false) { onAction?(action) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
        runLoopSource = nil
        eventTap = nil
        isRunning = false
    }

    func resetState() {
        _ = state.finish(commit: false)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let action = state.finish(commit: false) { emit(action, deferred: true) }
            if AXIsProcessTrusted(), let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard AXIsProcessTrusted() else {
            if let action = state.finish(commit: false) { emit(action, deferred: true) }
            isRunning = false
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        if type == .flagsChanged, state.isSwitching, !flags.contains(.maskCommand) {
            if let action = state.finish(commit: true) { emit(action, deferred: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if state.isSwitching {
            let action: SwitcherAction?
            switch keyCode {
            case Self.allWindowsKeyCode, Self.currentAppKeyCode:
                action = state.step(flags.contains(.maskShift) ? -1 : 1)
            case 126:
                action = state.step(-1)
            case 125:
                action = state.step(1)
            case 53:
                action = state.finish(commit: false)
            default:
                return Unmanaged.passUnretained(event)
            }
            if let action { onAction?(action) }
            return nil
        }

        let relevantFlags = flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        guard relevantFlags.contains(.maskCommand),
              !relevantFlags.contains(.maskControl),
              !relevantFlags.contains(.maskAlternate),
              onAction != nil else { return Unmanaged.passUnretained(event) }

        let currentAppOnly: Bool
        if keyCode == Self.allWindowsKeyCode {
            currentAppOnly = false
        } else if keyCode == Self.currentAppKeyCode {
            currentAppOnly = true
        } else {
            return Unmanaged.passUnretained(event)
        }

        let allowed = canBegin?(currentAppOnly) ?? true
        guard let action = state.begin(
            currentAppOnly: currentAppOnly,
            reverse: relevantFlags.contains(.maskShift),
            allowed: allowed
        ) else { return Unmanaged.passUnretained(event) }
        onAction?(action)
        return nil
    }

    private func emit(_ action: SwitcherAction, deferred: Bool) {
        guard deferred else {
            onAction?(action)
            return
        }
        DispatchQueue.main.async { [weak self] in self?.onAction?(action) }
    }

    private func observeSessionChanges() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if let action = self.state.finish(commit: false) { self.onAction?(action) }
                    if let eventTap = self.eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
                    self.isRunning = false
                }
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard AXIsProcessTrusted(), let eventTap = self?.eventTap else { return }
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                    self?.isRunning = true
                }
            }
        ]
    }

    static func selfCheck() -> Bool {
        var state = ShortcutState()
        guard allWindowsKeyCode == 48,
              currentAppKeyCode == 50,
              state.begin(currentAppOnly: false, reverse: false, allowed: false) == nil,
              state.begin(currentAppOnly: false, reverse: false, allowed: true) == .begin(currentAppOnly: false, reverse: false),
              state.step(1) == .step(1),
              state.finish(commit: false) == .cancel,
              state.begin(currentAppOnly: true, reverse: true, allowed: true) == .begin(currentAppOnly: true, reverse: true),
              state.finish(commit: true) == .commit,
              state.finish(commit: true) == nil else { return false }
        return true
    }
}

private let shortcutEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { controller.handle(type: type, event: event) }
}
