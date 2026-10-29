import AppKit
import ApplicationServices
import Darwin
import OpenContextsCore

enum WindowSpaces {
    struct DiscoveryState: @unchecked Sendable {
        var cursor: UInt64 = 0
        var unresolved: Set<CGWindowID> = []
        var windows: [CGWindowID: AXUIElement] = [:]
    }

    struct Snapshot: Sendable {
        let spaces: [WindowSpace]
        let membership: [CGWindowID: [WindowSpace]]
        let owners: [CGWindowID: pid_t]

        func space(for windowID: CGWindowID?) -> WindowSpace? {
            guard let windowID, let spaces = membership[windowID] else { return nil }
            return spaces.first(where: \.isCurrent) ?? spaces.first
        }
    }

    private struct API {
        let connection: @convention(c) () -> Int32
        let displays: @convention(c) (Int32) -> Unmanaged<CFArray>?
        let windows: @convention(c) (Int32, UInt32, CFArray, UInt32,
                                    UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?
        let windowID: @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
        let element: @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    }

    // Load the read-only private APIs at runtime so unsupported macOS versions can fall back safely.
    private static let api: API? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connection = dlsym(library, "SLSMainConnectionID"),
              let displays = dlsym(library, "SLSCopyManagedDisplaySpaces"),
              let windows = dlsym(library, "SLSCopyWindowsWithOptionsAndTags"),
              let windowID = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow"),
              let element = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken") else { return nil }
        return API(connection: unsafeBitCast(connection, to: (@convention(c) () -> Int32).self),
                   displays: unsafeBitCast(displays, to: (@convention(c) (Int32) -> Unmanaged<CFArray>?).self),
                   windows: unsafeBitCast(windows, to: (@convention(c) (Int32, UInt32, CFArray, UInt32,
                       UnsafeMutablePointer<UInt64>, UnsafeMutablePointer<UInt64>) -> Unmanaged<CFArray>?).self),
                   windowID: unsafeBitCast(windowID, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self),
                   element: unsafeBitCast(element, to: (@convention(c) (CFData) -> Unmanaged<AXUIElement>?).self))
    }()

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard api?.windowID(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func query() -> Snapshot? {
        guard let api, let displays = api.displays(api.connection())?.takeRetainedValue() as? [[String: Any]],
              !displays.isEmpty else { return nil }
        var spaces: [WindowSpace] = []
        var membership: [CGWindowID: [WindowSpace]] = [:]
        for display in displays {
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let displayID = display["Display Identifier"] as? String
            for raw in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = raw["id64"] as? NSNumber else { continue }
                let space = WindowSpace(id: id.uint64Value, index: spaces.count + 1,
                                        isCurrent: id == current, isFullscreen: (raw["type"] as? Int) == 4,
                                        displayID: displayID)
                spaces.append(space)
                var setTags: UInt64 = 0, clearTags: UInt64 = 0
                let ids = api.windows(api.connection(), 0, [id] as CFArray, 7, &setTags, &clearTags)?
                    .takeRetainedValue() as? [NSNumber] ?? []
                for window in ids { membership[window.uint32Value, default: []].append(space) }
            }
        }
        guard !spaces.isEmpty else { return nil }
        var owners: [CGWindowID: pid_t] = [:]
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = window[kCGWindowNumber as String] as? NSNumber,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  membership[id.uint32Value] != nil else { continue }
            owners[id.uint32Value] = pid
        }
        return Snapshot(spaces: spaces, membership: membership, owners: owners)
    }

    static func discoverWindows(pid: pid_t, targets: Set<CGWindowID>, state: inout DiscoveryState) -> [AXUIElement] {
        guard let api, !targets.isEmpty else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        var remaining = targets.subtracting(state.windows.keys)
        if !remaining.isSubset(of: state.unresolved) { state.cursor = 0 }
        state.unresolved = remaining
        guard !remaining.isEmpty else { return targets.compactMap { state.windows[$0] } }
        while ProcessInfo.processInfo.systemUptime < deadline {
            // shortcut: remote AX tokens use an undocumented 20-byte ABI; revisit if macOS changes it.
            var token = Data()
            for value in [UInt32(bitPattern: pid), 0, 0x636f636f] {
                var field = value.littleEndian
                withUnsafeBytes(of: &field) { token.append(contentsOf: $0) }
            }
            var field = state.cursor.littleEndian
            withUnsafeBytes(of: &field) { token.append(contentsOf: $0) }
            guard let element = api.element(token as CFData)?.takeRetainedValue() else {
                state.cursor &+= 1
                continue
            }
            AXUIElementSetMessagingTimeout(element, 0.02)
            var id: CGWindowID = 0
            let idResult = api.windowID(element, &id)
            if idResult == .cannotComplete { break }
            guard idResult == .success, remaining.contains(id) else { state.cursor &+= 1; continue }
            var role: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            if roleResult == .cannotComplete { break }
            state.cursor &+= 1
            guard roleResult == .success,
                  role as? String == kAXWindowRole else { continue }
            state.windows[id] = element
            remaining.remove(id)
            if remaining.isEmpty { break }
        }
        state.unresolved = remaining
        return targets.compactMap { state.windows[$0] }
    }
}
