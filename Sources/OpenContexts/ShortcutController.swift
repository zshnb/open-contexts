@preconcurrency import ApplicationServices
import AppKit
import Combine

struct KeyboardShortcut: Codable, Equatable {
    static let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
    static let allWindows = KeyboardShortcut(keyCode: 48, modifiers: .maskCommand, keyLabel: "Tab")
    static let currentApp = KeyboardShortcut(keyCode: 50, modifiers: .maskCommand, keyLabel: "`")

    let keyCode: UInt16
    let modifierRawValue: UInt64
    let keyLabel: String

    init(keyCode: UInt16, modifiers: CGEventFlags, keyLabel: String) {
        self.keyCode = keyCode
        modifierRawValue = modifiers.rawValue
        self.keyLabel = keyLabel
    }

    var modifiers: CGEventFlags { CGEventFlags(rawValue: modifierRawValue) }
    var isValid: Bool {
        keyCode < 128 && keyCode != 53 && !(54...63).contains(keyCode)
            && !modifiers.isEmpty && modifiers.subtracting(Self.modifierMask).isEmpty
            && !keyLabel.isEmpty && keyLabel.count <= 20
    }
    var display: String {
        (modifiers.contains(.maskControl) ? "⌃" : "")
            + (modifiers.contains(.maskAlternate) ? "⌥" : "")
            + (modifiers.contains(.maskCommand) ? "⌘" : "") + keyLabel
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && flags.intersection(Self.modifierMask) == modifiers
    }

    func conflicts(with other: KeyboardShortcut) -> Bool {
        keyCode == other.keyCode && modifierRawValue == other.modifierRawValue
    }

    init?(event: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        guard !flags.contains(.maskShift) else { return nil }
        let names: [UInt16: String] = [
            36: "↩", 48: "Tab", 49: "Space", 51: "⌫", 76: "⌤", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟"
        ]
        let functionKeys: [UInt16: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9,
            109: 10, 103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20
        ]
        let label = names[event.keyCode] ?? functionKeys[event.keyCode].map { "F\($0)" }
            ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? ""
        self.init(keyCode: event.keyCode, modifiers: flags.intersection(Self.modifierMask), keyLabel: label)
        guard isValid else { return nil }
    }
}

enum SwitcherAction: Equatable {
    case begin(currentAppOnly: Bool, reverse: Bool)
    case step(Int)
    case commit
    case cancel
}

private struct ShortcutState {
    private(set) var isSwitching = false
    private(set) var heldModifiers: CGEventFlags = []
    private var shiftIsDown = false
    private var shiftTapPending = false

    mutating func begin(currentAppOnly: Bool, reverse: Bool, allowed: Bool,
                        modifiers: CGEventFlags = .maskCommand,
                        shiftHeld: Bool = false) -> SwitcherAction? {
        guard !isSwitching, allowed else { return nil }
        isSwitching = true
        heldModifiers = modifiers
        // Shift held before the switcher opened belongs to the opening shortcut, not a tap.
        shiftIsDown = shiftHeld
        shiftTapPending = false
        return .begin(currentAppOnly: currentAppOnly, reverse: reverse)
    }

    mutating func step(_ amount: Int) -> SwitcherAction? {
        guard isSwitching else { return nil }
        // A key that moves the selection resolves any pending Shift tap, so ⇧Tab stays one step.
        shiftTapPending = false
        return .step(amount)
    }

    /// Tracks Shift on its own: tapping it while switching steps back once, holding it still reverses ⇧Tab.
    mutating func shiftFlagsChanged(_ flags: CGEventFlags) -> SwitcherAction? {
        guard isSwitching else { return nil }
        guard !flags.contains(.maskShift) else {
            if !shiftIsDown {
                shiftIsDown = true
                shiftTapPending = true
            }
            return nil
        }
        shiftIsDown = false
        guard shiftTapPending else { return nil }
        shiftTapPending = false
        return .step(-1)
    }

    mutating func finish(commit: Bool) -> SwitcherAction? {
        guard isSwitching else { return nil }
        isSwitching = false
        heldModifiers = []
        shiftIsDown = false
        shiftTapPending = false
        return commit ? .commit : .cancel
    }
}

@MainActor
final class ShortcutController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var recordingCurrentAppOnly: Bool?
    @Published private(set) var recordingErrorKey: String?
    var onAction: ((SwitcherAction) -> Void)?
    var canBegin: ((Bool) -> Bool)?
    private(set) var allWindowsShortcut = KeyboardShortcut.allWindows
    private(set) var currentAppShortcut = KeyboardShortcut.currentApp

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var state = ShortcutState()
    private var recordingMonitor: Any?
    private var saveRecording: ((KeyboardShortcut) -> Bool)?

    func configure(allWindows: KeyboardShortcut, currentApp: KeyboardShortcut) {
        guard allWindows.isValid, currentApp.isValid, !allWindows.conflicts(with: currentApp),
              allWindows != allWindowsShortcut || currentApp != currentAppShortcut else { return }
        if let action = state.finish(commit: false) { onAction?(action) }
        allWindowsShortcut = allWindows
        currentAppShortcut = currentApp
    }

    func beginRecording(currentAppOnly: Bool, onSave: @escaping (KeyboardShortcut) -> Bool) {
        cancelRecording()
        if let action = state.finish(commit: false) { onAction?(action) }
        recordingCurrentAppOnly = currentAppOnly
        saveRecording = onSave
        // Also records in Settings before Accessibility permission is granted.
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let captured = MainActor.assumeIsolated {
                guard let self, self.recordingCurrentAppOnly != nil else { return false }
                self.record(event)
                return true
            }
            return captured ? nil : event
        }
    }

    func cancelRecording() {
        if let recordingMonitor { NSEvent.removeMonitor(recordingMonitor) }
        recordingMonitor = nil
        saveRecording = nil
        recordingCurrentAppOnly = nil
        recordingErrorKey = nil
    }

    private func record(_ event: NSEvent) {
        guard recordingCurrentAppOnly != nil, !event.isARepeat else { return }
        if event.keyCode == 53 {
            cancelRecording()
        } else if let shortcut = KeyboardShortcut(event: event) {
            if saveRecording?(shortcut) == true {
                cancelRecording()
            } else {
                recordingErrorKey = "The two shortcuts must be different."
            }
        } else {
            recordingErrorKey = "Use Command, Option or Control with a key; Shift is reserved for reverse switching."
        }
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if let eventTap {
            // The tap survives transient trust loss or session switches; re-enable it instead of no-op.
            CGEvent.tapEnable(tap: eventTap, enable: true)
            isRunning = true
            return true
        }

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
        cancelRecording()
        if let action = state.finish(commit: false) { onAction?(action) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
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
        if type == .flagsChanged {
            if let action = modifierAction(flags: flags) { emit(action, deferred: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        if recordingCurrentAppOnly != nil {
            // Defer AppKit/UI work until after the event tap returns, and swallow even ⌘Tab.
            if let keyEvent = NSEvent(cgEvent: event) {
                DispatchQueue.main.async { [weak self] in self?.record(keyEvent) }
            }
            return nil
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard onAction != nil, let action = keyAction(keyCode: keyCode, flags: flags) else {
            return Unmanaged.passUnretained(event)
        }
        onAction?(action)
        return nil
    }

    private func modifierAction(flags: CGEventFlags) -> SwitcherAction? {
        guard state.isSwitching else { return nil }
        guard flags.contains(state.heldModifiers) else { return state.finish(commit: true) }
        return state.shiftFlagsChanged(flags)
    }

    private func keyAction(keyCode: UInt16, flags: CGEventFlags) -> SwitcherAction? {
        if state.isSwitching {
            if allWindowsShortcut.matches(keyCode: keyCode, flags: flags)
                || currentAppShortcut.matches(keyCode: keyCode, flags: flags) {
                return state.step(flags.contains(.maskShift) ? -1 : 1)
            }
            switch keyCode {
            case 48, 50:
                return state.step(flags.contains(.maskShift) ? -1 : 1)
            case 126:
                return state.step(-1)
            case 125:
                return state.step(1)
            case 53:
                return state.finish(commit: false)
            default:
                return nil
            }
        }

        let currentAppOnly: Bool
        let shortcut: KeyboardShortcut
        if allWindowsShortcut.matches(keyCode: keyCode, flags: flags) {
            currentAppOnly = false
            shortcut = allWindowsShortcut
        } else if currentAppShortcut.matches(keyCode: keyCode, flags: flags) {
            currentAppOnly = true
            shortcut = currentAppShortcut
        } else {
            return nil
        }

        return state.begin(
            currentAppOnly: currentAppOnly,
            reverse: flags.contains(.maskShift),
            allowed: canBegin?(currentAppOnly) ?? true,
            modifiers: shortcut.modifiers,
            shiftHeld: flags.contains(.maskShift)
        )
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
                    self.cancelRecording()
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
        guard KeyboardShortcut.allWindows.display == "⌘Tab",
              KeyboardShortcut.currentApp.display == "⌘`",
              state.begin(currentAppOnly: false, reverse: false, allowed: false) == nil,
              state.begin(currentAppOnly: false, reverse: false, allowed: true) == .begin(currentAppOnly: false, reverse: false),
              state.step(1) == .step(1),
              state.finish(commit: false) == .cancel,
              state.begin(currentAppOnly: true, reverse: true, allowed: true,
                          shiftHeld: true) == .begin(currentAppOnly: true, reverse: true),
              state.finish(commit: true) == .commit,
              state.finish(commit: true) == nil else { return false }

        let controller = ShortcutController()
        guard controller.keyAction(keyCode: 48, flags: []) == nil,
              controller.keyAction(keyCode: 48, flags: [.maskCommand, .maskControl]) == nil,
              controller.keyAction(keyCode: 48, flags: [.maskCommand, .maskShift])
                == .begin(currentAppOnly: false, reverse: true),
              controller.keyAction(keyCode: 48, flags: [.maskCommand, .maskShift]) == .step(-1),
              controller.keyAction(keyCode: 50, flags: .maskCommand) == .step(1),
              controller.modifierAction(flags: [.maskCommand, .maskShift]) == nil,
              controller.modifierAction(flags: .maskShift) == .commit,
              controller.keyAction(keyCode: 50, flags: .maskCommand)
                == .begin(currentAppOnly: true, reverse: false),
              controller.keyAction(keyCode: 53, flags: .maskCommand) == .cancel else { return false }

        // Tapping Shift alone moves back one step and leaves ⇧Tab at one step; Shift held from the
        // opening shortcut is never mistaken for a tap.
        let tappedShift = ShortcutController()
        let shiftHeldFromStart = ShortcutController()
        guard tappedShift.modifierAction(flags: [.maskShift]) == nil,
              tappedShift.keyAction(keyCode: 48, flags: .maskCommand)
                == .begin(currentAppOnly: false, reverse: false),
              tappedShift.modifierAction(flags: [.maskCommand, .maskShift]) == nil,
              tappedShift.modifierAction(flags: .maskCommand) == .step(-1),
              tappedShift.modifierAction(flags: .maskCommand) == nil,
              tappedShift.modifierAction(flags: [.maskCommand, .maskShift]) == nil,
              tappedShift.keyAction(keyCode: 48, flags: [.maskCommand, .maskShift]) == .step(-1),
              tappedShift.modifierAction(flags: .maskCommand) == nil,
              tappedShift.keyAction(keyCode: 48, flags: .maskCommand) == .step(1),
              tappedShift.keyAction(keyCode: 53, flags: .maskCommand) == .cancel,
              shiftHeldFromStart.keyAction(keyCode: 48, flags: [.maskCommand, .maskShift])
                == .begin(currentAppOnly: false, reverse: true),
              shiftHeldFromStart.modifierAction(flags: .maskCommand) == nil,
              shiftHeldFromStart.keyAction(keyCode: 48, flags: [.maskCommand, .maskShift]) == .step(-1),
              shiftHeldFromStart.keyAction(keyCode: 53, flags: .maskCommand) == .cancel else { return false }

        let custom = KeyboardShortcut(keyCode: 16, modifiers: [.maskControl, .maskAlternate], keyLabel: "Y")
        let sameKey = KeyboardShortcut(keyCode: 16, modifiers: .maskCommand, keyLabel: "Y")
        guard custom.isValid, custom.display == "⌃⌥Y", !custom.conflicts(with: sameKey),
              !KeyboardShortcut(keyCode: 16, modifiers: [], keyLabel: "Y").isValid,
              !KeyboardShortcut(keyCode: 16, modifiers: [.maskCommand, .maskShift], keyLabel: "Y").isValid,
              !KeyboardShortcut(keyCode: 53, modifiers: .maskCommand, keyLabel: "Esc").isValid else { return false }
        controller.configure(allWindows: custom, currentApp: sameKey)
        guard controller.keyAction(keyCode: 48, flags: .maskCommand) == nil,
              controller.keyAction(keyCode: 50, flags: .maskCommand) == nil,
              controller.keyAction(keyCode: 16, flags: .maskControl) == nil,
              controller.keyAction(keyCode: 16, flags: [.maskControl, .maskAlternate, .maskShift])
                == .begin(currentAppOnly: false, reverse: true),
              controller.keyAction(keyCode: 16, flags: custom.modifiers) == .step(1),
              controller.keyAction(keyCode: 48, flags: [.maskControl, .maskAlternate, .maskShift]) == .step(-1),
              controller.keyAction(keyCode: 126, flags: custom.modifiers) == .step(-1),
              controller.keyAction(keyCode: 125, flags: custom.modifiers) == .step(1),
              controller.keyAction(keyCode: 0, flags: custom.modifiers) == nil,
              controller.modifierAction(flags: [.maskControl, .maskAlternate, .maskShift]) == nil,
              controller.modifierAction(flags: .maskControl) == .commit,
              controller.keyAction(keyCode: 16, flags: .maskCommand)
                == .begin(currentAppOnly: true, reverse: false),
              controller.modifierAction(flags: []) == .commit else { return false }
        controller.canBegin = { _ in false }
        guard controller.keyAction(keyCode: 16, flags: custom.modifiers) == nil else { return false }
        controller.canBegin = nil
        guard controller.keyAction(keyCode: 16, flags: custom.modifiers) != nil else { return false }
        var cancelled = false
        controller.onAction = { cancelled = $0 == .cancel }
        controller.configure(allWindows: .allWindows, currentApp: .currentApp)
        guard cancelled, controller.modifierAction(flags: []) == nil else { return false }
        controller.configure(allWindows: .allWindows, currentApp: .allWindows)
        guard controller.currentAppShortcut == .currentApp else { return false }

        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                          modifierFlags: [.control, .option], timestamp: 0,
                                          windowNumber: 0, context: nil, characters: "y",
                                          charactersIgnoringModifiers: "y", isARepeat: false, keyCode: 16),
              let recorded = KeyboardShortcut(event: event),
              recorded.matches(keyCode: 16, flags: custom.modifiers), recorded.keyLabel == "Y" else { return false }

        var acceptRecording = false
        var saved: KeyboardShortcut?
        controller.beginRecording(currentAppOnly: false) { shortcut in
            guard acceptRecording else { return false }
            saved = shortcut
            return true
        }
        defer { controller.cancelRecording() }
        controller.record(event)
        guard controller.recordingCurrentAppOnly == false,
              controller.recordingErrorKey == "The two shortcuts must be different.", saved == nil else { return false }
        acceptRecording = true
        controller.record(event)
        guard saved == recorded, controller.recordingCurrentAppOnly == nil,
              controller.recordingMonitor == nil, controller.recordingErrorKey == nil else { return false }
        controller.beginRecording(currentAppOnly: true) { _ in false }
        guard let invalid = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: 0, context: nil, characters: "y",
                                            charactersIgnoringModifiers: "y", isARepeat: false, keyCode: 16),
              let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, characters: "\u{1b}",
                                           charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) else { return false }
        controller.record(invalid)
        guard controller.recordingCurrentAppOnly == true, controller.recordingErrorKey != nil else { return false }
        controller.record(escape)
        guard controller.recordingCurrentAppOnly == nil, controller.recordingMonitor == nil,
              controller.recordingErrorKey == nil else { return false }
        return true
    }
}

private let shortcutEventCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ShortcutController>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { controller.handle(type: type, event: event) }
}
