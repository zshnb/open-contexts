import AppKit
import OpenContextsCore

private let rowHoverColor = NSColor(srgbRed: 80 / 255, green: 151 / 255,
                                    blue: 247 / 255, alpha: 1)

@MainActor
final class SidebarPanel: NSPanel {
    typealias WindowMove = (_ id: String, _ groupID: String, _ beforeWindowID: String?) -> Void
    typealias GroupMove = (_ id: String, _ beforeGroupID: String?) -> Void

    private let sidebarWidth: CGFloat = 188
    private let edgeWidth: CGFloat = 8
    private let rootView = NSView()
    private let effect = NSVisualEffectView()
    private let scroll = NSScrollView()
    private let stack = FlippedStackView()
    private let onActivate: (String) -> Void
    private let onMoveWindow: WindowMove
    private let onMoveGroup: GroupMove
    private let onCreateGroup: (String) -> Void
    private let onRenameGroup: (String, String) -> Void
    private let onDeleteGroup: (String) -> Void
    private var displayScreen: NSScreen
    private var alwaysVisible = false
    private var fullscreen = false
    private var position: SidebarPosition = .right
    private var hoverState = SidebarHoverState()
    private var hoverTimer: Timer?
    private var dragging = false
    private var sourceDragging = false
    private var destinationDragging = false
    private var originalRowOrder: [SidebarItemView]?
    private var renderedGroups: [WindowGroup] = []
    private var renderedWindows: [String: [WindowInfo]] = [:]
    private var renderedPosition: SidebarPosition = .right
    private var naturalContentHeight: CGFloat = 52
    private var pendingUpdate: PendingSidebarUpdate?
    private var iconRetryTasks: [String: Task<Void, Never>] = [:]
    private var iconRetrySchedules: [String: IconRetrySchedule] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var renderedBadges: [String: String] = [:]
    private var positionConstraints: [NSLayoutConstraint] = []
    private var stackCrossAxisConstraint: NSLayoutConstraint?
    private var previewDrop: SidebarDrop?

    private struct PendingSidebarUpdate {
        let groups: [WindowGroup]
        let windowsByGroup: [String: [WindowInfo]]
        let alwaysVisible: Bool
        let fullscreen: Bool
        let position: SidebarPosition
    }

    private enum SidebarDrop: Equatable {
        case window(id: String, groupID: String, beforeWindowID: String?)
        case group(id: String, beforeGroupID: String?)
    }

    init(screen: NSScreen, onActivate: @escaping (String) -> Void,
         onMoveWindow: @escaping WindowMove, onMoveGroup: @escaping GroupMove,
         onCreateGroup: @escaping (String) -> Void,
         onRenameGroup: @escaping (String, String) -> Void,
         onDeleteGroup: @escaping (String) -> Void) {
        self.displayScreen = screen
        self.onActivate = onActivate
        self.onMoveWindow = onMoveWindow
        self.onMoveGroup = onMoveGroup
        self.onCreateGroup = onCreateGroup
        self.onRenameGroup = onRenameGroup
        self.onDeleteGroup = onDeleteGroup
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.onDraggingUpdated = { [weak self] in self?.updateDragPreview($0) ?? [] }
        stack.onPerformDrag = { [weak self] in self?.performDrop($0) ?? false }
        stack.onDraggingChanged = { [weak self] active, restore in
            self?.destinationDraggingChanged(active, restorePreview: restore)
        }
        scroll.documentView = stack

        rootView.addSubview(effect)
        effect.addSubview(scroll)
        contentView = rootView
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: effect.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        configurePosition()
        layoutPanel(animated: false)
        layoutDocumentView()
        startHoverPolling()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func close() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        cancelIconRetries()
        super.close()
    }

    func update(groups: [WindowGroup], windowsByGroup: [String: [WindowInfo]],
                alwaysVisible: Bool, fullscreen: Bool, position: SidebarPosition = .right) {
        let presentationChanged = self.alwaysVisible != alwaysVisible || self.fullscreen != fullscreen
        self.alwaysVisible = alwaysVisible
        self.fullscreen = fullscreen
        guard !dragging else {
            pendingUpdate = PendingSidebarUpdate(groups: groups, windowsByGroup: windowsByGroup,
                                                 alwaysVisible: alwaysVisible, fullscreen: fullscreen,
                                                 position: position)
            layoutPanel(animated: false)
            return
        }
        self.position = position
        let positionChanged = renderedPosition != position
        if positionChanged {
            renderedPosition = position
            configurePosition()
        }
        guard groups != renderedGroups || windowsByGroup != renderedWindows || positionChanged else {
            if presentationChanged { layoutPanel(animated: false) }
            return
        }
        renderedGroups = groups
        renderedWindows = windowsByGroup
        let activeIconKeys = Set(windowsByGroup.values.flatMap { $0 }.map(applicationIconKey))
        for key in iconRetryTasks.keys.filter({ !activeIconKeys.contains($0) }) {
            iconRetryTasks.removeValue(forKey: key)?.cancel()
        }
        iconRetrySchedules = iconRetrySchedules.filter { activeIconKeys.contains($0.key) }
        iconCache = iconCache.filter { activeIconKeys.contains($0.key) }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for group in groups {
            let header = SidebarItemView(
                title: group.name,
                style: .group(id: group.id),
                onClick: nil,
                onDraggingChanged: { [weak self] in self?.sourceDraggingChanged($0) }
            )
            if group.id != GroupStore.ungroupedID {
                let menu = NSMenu()
                let rename = NSMenuItem(title: "重命名", action: #selector(renameGroup(_:)), keyEquivalent: "")
                rename.target = self
                rename.representedObject = group.id
                let delete = NSMenuItem(title: "删除分组", action: #selector(deleteGroup(_:)), keyEquivalent: "")
                delete.target = self
                delete.representedObject = group.id
                menu.items = [rename, delete]
                header.menu = menu
            }
            stack.addArrangedSubview(header)
            constrainSidebarItem(header)

            for window in windowsByGroup[group.id, default: []] {
                let iconKey = applicationIconKey(for: window)
                let icon = iconCache[iconKey]
                    ?? (iconRetrySchedules[iconKey] == nil ? resolvedApplicationIcon(for: window) : nil)
                if let icon { iconCache[iconKey] = icon }
                let row = SidebarItemView(
                    title: window.displayTitle,
                    icon: icon ?? fallbackApplicationIcon(for: window),
                    iconKey: iconKey,
                    badgeKey: window.appID,
                    badge: renderedBadges[window.appID],
                    style: .window(id: window.id, groupID: group.id),
                    onClick: { [weak self] in self?.onActivate(window.id) },
                    onDraggingChanged: { [weak self] in self?.sourceDraggingChanged($0) }
                )
                stack.addArrangedSubview(row)
                constrainSidebarItem(row)
                if icon == nil, iconRetrySchedules[iconKey] == nil {
                    iconRetrySchedules[iconKey] = IconRetrySchedule()
                    retryApplicationIcon(for: window, iconKey: iconKey)
                }
            }
        }
        let create = CallbackButton(title: "＋ 新建分组") { [weak self] in self?.createGroup() }
        stack.addArrangedSubview(create)
        create.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        let endDrop = GroupEndDropView()
        stack.addArrangedSubview(endDrop)
        endDrop.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        naturalContentHeight = Self.contentHeight(groupCount: groups.count,
                                                  windowCount: groups.reduce(0) {
            $0 + windowsByGroup[$1.id, default: []].count
        })
        layoutPanel(animated: false)
        layoutDocumentView()
    }

    func updateBadges(_ badges: [String: String]) {
        guard badges != renderedBadges else { return }
        renderedBadges = badges
        sidebarRows.forEach { $0.setBadge($0.badgeKey.flatMap { badges[$0] }) }
    }

    private func retryApplicationIcon(for window: WindowInfo, iconKey: String) {
        iconRetryTasks[iconKey] = Task { [weak self] in
            while var schedule = self?.iconRetrySchedules[iconKey],
                  let delay = schedule.nextDelay() {
                self?.iconRetrySchedules[iconKey] = schedule
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                if let icon = resolvedApplicationIcon(for: window) {
                    self.iconCache[iconKey] = icon
                    self.iconRetrySchedules[iconKey]?.stop()
                    self.stack.arrangedSubviews.compactMap { $0 as? SidebarItemView }
                        .filter { $0.iconKey == iconKey }
                        .forEach { $0.setIcon(icon) }
                    self.iconRetryTasks[iconKey] = nil
                    return
                }
            }
            self?.iconRetryTasks[iconKey] = nil
        }
    }

    private func cancelIconRetries() {
        iconRetryTasks.values.forEach { $0.cancel() }
        iconRetryTasks.removeAll()
    }

    private func restartExhaustedIconRetries() {
        for window in renderedWindows.values.flatMap({ $0 }) {
            let iconKey = applicationIconKey(for: window)
            guard iconCache[iconKey] == nil, iconRetryTasks[iconKey] == nil,
                  iconRetrySchedules[iconKey]?.isExhausted == true else { continue }
            iconRetrySchedules[iconKey] = IconRetrySchedule()
            retryApplicationIcon(for: window, iconKey: iconKey)
        }
    }

    func move(to screen: NSScreen) {
        displayScreen = screen
        layoutPanel(animated: false)
        layoutDocumentView()
    }

    private func layoutPanel(animated _: Bool) {
        let frames = sidebarFrames()
        let expanded = hoverState.isExpanded || dragging || (alwaysVisible && !fullscreen)
        let target = expanded ? frames.expanded : frames.edge
        if expanded {
            if !frame.approximatelyEquals(target) { setFrame(target, display: true) }
            if !isVisible {
                restartExhaustedIconRetries()
                orderFrontRegardless()
            }
        } else {
            if isVisible { orderOut(nil) }
            if !frame.approximatelyEquals(target) { setFrame(target, display: false) }
        }
    }

    private func sidebarFrames() -> (edge: NSRect, expanded: NSRect) {
        let area = fullscreen ? displayScreen.frame : displayScreen.visibleFrame
        let height = min(naturalContentHeight, area.height)
        let y = area.midY - height / 2
        switch position {
        case .left:
            return (
                NSRect(x: area.minX, y: y, width: edgeWidth, height: height),
                NSRect(x: area.minX, y: y, width: sidebarWidth, height: height)
            )
        case .right:
            return (
                NSRect(x: area.maxX - edgeWidth, y: y, width: edgeWidth, height: height),
                NSRect(x: area.maxX - sidebarWidth, y: y, width: sidebarWidth, height: height)
            )
        }
    }

    private func startHoverPolling() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHover(pointer: NSEvent.mouseLocation,
                                  now: ProcessInfo.processInfo.systemUptime)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func updateHover(pointer: CGPoint, now: TimeInterval) {
        let frames = sidebarFrames()
        if hoverState.update(pointer: pointer, edgeFrame: frames.edge, expandedFrame: frames.expanded,
                             dragging: dragging, now: now) {
            layoutPanel(animated: false)
        }
    }

    private func sourceDraggingChanged(_ active: Bool) {
        sourceDragging = active
        if !active { destinationDragging = false }
        updateDraggingState()
    }

    private func destinationDraggingChanged(_ active: Bool, restorePreview: Bool) {
        destinationDragging = active
        if restorePreview { restorePreviewOrder() }
        updateDraggingState()
    }

    private func updateDraggingState() {
        let active = sourceDragging || destinationDragging
        guard dragging != active else { return }
        dragging = active
        updateHover(pointer: NSEvent.mouseLocation, now: ProcessInfo.processInfo.systemUptime)
        guard !active else {
            originalRowOrder = sidebarRows
            previewDrop = nil
            return
        }
        let next = pendingUpdate ?? PendingSidebarUpdate(
            groups: renderedGroups, windowsByGroup: renderedWindows,
            alwaysVisible: alwaysVisible, fullscreen: fullscreen, position: position
        )
        self.pendingUpdate = nil
        previewDrop = nil
        originalRowOrder = nil
        renderedGroups = []
        renderedWindows = [:]
        update(groups: next.groups, windowsByGroup: next.windowsByGroup,
               alwaysVisible: next.alwaysVisible, fullscreen: next.fullscreen,
               position: next.position)
    }

    private func restorePreviewOrder() {
        guard previewDrop != nil, let originalRowOrder,
              Set(originalRowOrder.map(ObjectIdentifier.init)) == Set(sidebarRows.map(ObjectIdentifier.init)) else {
            previewDrop = nil
            return
        }
        sidebarRows.forEach { stack.removeArrangedSubview($0) }
        for (index, row) in originalRowOrder.enumerated() { stack.insertArrangedSubview(row, at: index) }
        previewDrop = nil
        stack.needsLayout = true
        layoutDocumentView()
    }

    private func updateDragPreview(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let drop = proposedDrop(sender) else { return [] }
        preview(drop)
        return .move
    }

    private func preview(_ drop: SidebarDrop) {
        if previewDrop != drop {
            previewDrop = drop
            applyPreview(drop)
        }
    }

    private func performDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let drop = proposedDrop(sender) else { return false }
        commit(drop)
        return true
    }

    private func commit(_ drop: SidebarDrop) {
        switch drop {
        case let .window(id, groupID, beforeWindowID):
            onMoveWindow(id, groupID, beforeWindowID)
        case let .group(id, beforeGroupID):
            if id != beforeGroupID { onMoveGroup(id, beforeGroupID) }
        }
    }

    private func proposedDrop(_ sender: NSDraggingInfo) -> SidebarDrop? {
        let pasteboard = sender.draggingPasteboard
        let y = stack.convert(sender.draggingLocation, from: nil).y
        if let id = pasteboard.string(forType: .openContextsWindow),
           let destination = windowDestination(at: y) {
            return normalizedWindowDrop(id: id, destination: destination)
        }
        if let id = pasteboard.string(forType: .openContextsGroup) {
            guard id != GroupStore.ungroupedID else { return nil }
            let beforeGroupID = groupDestination(at: y)
            guard beforeGroupID != GroupStore.ungroupedID else { return nil }
            if beforeGroupID == id {
                guard case .group(let previewID, _)? = previewDrop, previewID == id else { return nil }
                return previewDrop
            }
            return .group(id: id, beforeGroupID: beforeGroupID)
        }
        return nil
    }

    private func normalizedWindowDrop(
        id: String, destination: (groupID: String, beforeWindowID: String?)
    ) -> SidebarDrop? {
        if destination.beforeWindowID == id {
            guard case .window(let previewID, _, _)? = previewDrop, previewID == id else { return nil }
            return previewDrop
        }
        return .window(id: id, groupID: destination.groupID,
                       beforeWindowID: destination.beforeWindowID)
    }

    private func windowDestination(at y: CGFloat) -> (groupID: String, beforeWindowID: String?)? {
        let rows = sidebarRows
        var currentGroup: String?
        for (index, row) in rows.enumerated() {
            switch row.style {
            case .group(let id):
                currentGroup = id
                if y <= row.frame.maxY { return (id, nil) }
            case .window(let id, _):
                guard let currentGroup else { continue }
                if y <= row.frame.midY { return (currentGroup, id) }
                if y <= row.frame.maxY {
                    let nextID: String? = rows.dropFirst(index + 1).prefix { row in
                        if case .window = row.style { return true }
                        return false
                    }.compactMap { row in
                        if case .window(let id, _) = row.style { return id }
                        return nil
                    }.first
                    return (currentGroup, nextID)
                }
            }
        }
        return currentGroup.map { ($0, nil) }
    }

    private func groupDestination(at y: CGFloat) -> String? {
        for row in sidebarRows {
            if case .group(let id) = row.style, y <= row.frame.midY { return id }
        }
        return nil
    }

    private var sidebarRows: [SidebarItemView] {
        stack.arrangedSubviews.compactMap { $0 as? SidebarItemView }
    }

    private func applyPreview(_ drop: SidebarDrop) {
        var rows = sidebarRows
        switch drop {
        case let .window(id, groupID, beforeWindowID):
            guard beforeWindowID != id else { return }
            guard let source = rows.first(where: {
                if case .window(let rowID, _) = $0.style { return rowID == id }
                return false
            }) else { return }
            rows.removeAll { $0 === source }
            guard let groupIndex = rows.firstIndex(where: {
                if case .group(let rowID) = $0.style { return rowID == groupID }
                return false
            }) else { return }
            let insertionIndex: Int
            if let beforeWindowID,
               let index = rows.firstIndex(where: {
                   if case .window(let rowID, _) = $0.style { return rowID == beforeWindowID }
                   return false
               }) {
                insertionIndex = index
            } else {
                insertionIndex = rows[(groupIndex + 1)...].firstIndex(where: {
                    if case .group = $0.style { return true }
                    return false
                }) ?? rows.endIndex
            }
            rows.insert(source, at: insertionIndex)
        case let .group(id, beforeGroupID):
            guard id != GroupStore.ungroupedID, beforeGroupID != GroupStore.ungroupedID,
                  id != beforeGroupID else { return }
            guard let start = rows.firstIndex(where: {
                if case .group(let rowID) = $0.style { return rowID == id }
                return false
            }) else { return }
            let end = rows[(start + 1)...].firstIndex(where: {
                if case .group = $0.style { return true }
                return false
            }) ?? rows.endIndex
            let block = Array(rows[start..<end])
            rows.removeSubrange(start..<end)
            let insertionIndex = beforeGroupID.flatMap { target in
                rows.firstIndex(where: {
                    if case .group(let rowID) = $0.style { return rowID == target }
                    return false
                })
            } ?? rows.endIndex
            rows.insert(contentsOf: block, at: insertionIndex)
        }
        sidebarRows.forEach { stack.removeArrangedSubview($0) }
        for (index, row) in rows.enumerated() { stack.insertArrangedSubview(row, at: index) }
        stack.needsLayout = true
        layoutDocumentView()
    }

    private func configurePosition() {
        NSLayoutConstraint.deactivate(positionConstraints)
        stackCrossAxisConstraint?.isActive = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 4, bottom: 6, right: 4)
        effect.layer?.maskedCorners = position == .left
            ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        stackCrossAxisConstraint = stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        positionConstraints = [
            effect.widthAnchor.constraint(equalToConstant: sidebarWidth),
            effect.topAnchor.constraint(equalTo: rootView.topAnchor),
            effect.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            position == .left
                ? effect.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
                : effect.trailingAnchor.constraint(equalTo: rootView.trailingAnchor)
        ]
        NSLayoutConstraint.activate(positionConstraints)
        stackCrossAxisConstraint?.isActive = true
    }

    private func constrainSidebarItem(_ view: NSView) {
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
    }

    private func layoutDocumentView() {
        rootView.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        stack.setFrameSize(NSSize(width: max(scroll.contentSize.width, 1),
                                  height: max(naturalContentHeight, scroll.contentSize.height)))
        stack.layoutSubtreeIfNeeded()
    }

    private static func contentHeight(groupCount: Int, windowCount: Int) -> CGFloat {
        12 + CGFloat(groupCount * 32 + windowCount * 25 + 30 + 12)
    }

    private func createGroup() {
        requestName(title: "新建分组", value: "") { [weak self] name in self?.onCreateGroup(name) }
    }

    @objc private func renameGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let name = renderedGroups.first(where: { $0.id == id })?.name ?? ""
        requestName(title: "重命名分组", value: name) { [weak self] name in self?.onRenameGroup(id, name) }
    }

    @objc private func deleteGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onDeleteGroup(id)
    }

    private func requestName(title: String, value: String, completion: (String) -> Void) {
        let field = NSTextField(string: value)
        field.frame.size = NSSize(width: 240, height: 24)
        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = field
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        completion(field.stringValue)
    }

    fileprivate var smokeRowsAreCompact: Bool {
        let rows = stack.arrangedSubviews.compactMap { $0 as? SidebarItemView }
        return !rows.isEmpty && rows.allSatisfy(\.smokeHeightIsValid)
    }

    fileprivate var smokeRowHoverAppearanceIsValid: Bool {
        stack.arrangedSubviews.compactMap { $0 as? SidebarItemView }
            .allSatisfy(\.smokeHoverAppearanceIsValid)
    }

    fileprivate var smokePositionLayoutIsValid: Bool {
        positionConstraints.count == 4 && positionConstraints.allSatisfy(\.isActive)
            && stackCrossAxisConstraint?.isActive == true
            && stack.orientation == .vertical
            && stack.spacing == 0
    }

    fileprivate var smokeNaturalContentHeight: CGFloat { naturalContentHeight }
    fileprivate var smokeRowOrder: [String] {
        sidebarRows.map {
            switch $0.style {
            case .group(let id): "g:\(id)"
            case .window(let id, _): "w:\(id)"
            }
        }
    }
    fileprivate func smokeWindowIdentity(_ id: String) -> ObjectIdentifier? {
        sidebarRows.first {
            if case .window(let rowID, _) = $0.style { return rowID == id }
            return false
        }.map(ObjectIdentifier.init)
    }
    fileprivate func smokeBeginDrag() { sourceDraggingChanged(true) }
    fileprivate func smokePreviewWindow(_ id: String, groupID: String, beforeWindowID: String?) {
        preview(.window(id: id, groupID: groupID, beforeWindowID: beforeWindowID))
    }
    fileprivate func smokeWindowSelfHitKeepsPreview(_ id: String, groupID: String) -> Bool {
        let before = smokeRowOrder
        guard let drop = normalizedWindowDrop(
            id: id, destination: (groupID: groupID, beforeWindowID: id)
        ) else { return false }
        preview(drop)
        return smokeRowOrder == before
    }
    fileprivate func smokePreviewGroup(_ id: String, beforeGroupID: String?) {
        preview(.group(id: id, beforeGroupID: beforeGroupID))
    }
    fileprivate func smokeDestinationExited() {
        destinationDraggingChanged(false, restorePreview: true)
    }
    fileprivate func smokeDestinationEntered() {
        destinationDraggingChanged(true, restorePreview: false)
    }
    fileprivate var smokeIsDragging: Bool { dragging }
    fileprivate func smokeCommitPreview() {
        if let previewDrop { commit(previewDrop) }
    }
    fileprivate func smokeEndDrag() { sourceDraggingChanged(false) }
    fileprivate var smokeHasOverflow: Bool {
        naturalContentHeight > scroll.contentSize.height && stack.frame.height > scroll.contentSize.height
    }

    fileprivate func smokeScrollLastWindowIntoView() -> Bool {
        guard let row = stack.arrangedSubviews.compactMap({ $0 as? SidebarItemView }).last else { return false }
        row.scrollToVisible(row.bounds)
        scroll.reflectScrolledClipView(scroll.contentView)
        return scroll.contentView.bounds.intersects(row.convert(row.bounds, to: scroll.contentView))
    }

    fileprivate func smokeStopHoverPolling() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    fileprivate func smokeApplyBadges(_ badges: [String: String]) { updateBadges(badges) }
    fileprivate func smokeBadgesAreValid(text: String, diameter: CGFloat) -> Bool {
        let rows = sidebarRows.filter { if case .window = $0.style { return true }; return false }
        return !rows.isEmpty && rows.allSatisfy { $0.smokeBadgeIsValid(text: text, diameter: diameter) }
    }
    fileprivate var smokeDotBadgesAreValid: Bool {
        let rows = sidebarRows.filter { if case .window = $0.style { return true }; return false }
        return !rows.isEmpty && rows.allSatisfy(\.smokeDotBadgeIsValid)
    }

    fileprivate var smokeBadgesAreHidden: Bool {
        let rows = sidebarRows.filter { if case .window = $0.style { return true }; return false }
        return !rows.isEmpty && rows.allSatisfy(\.smokeBadgeIsHidden)
    }

    fileprivate var smokeBadgeLayoutDescription: String {
        sidebarRows.compactMap { $0.smokeBadgeLayoutDescription }.joined(separator: ", ")
    }

    fileprivate var smokeSidebarFrames: (edge: NSRect, expanded: NSRect) { sidebarFrames() }
    fileprivate var smokeIsHidden: Bool { !isVisible }
    fileprivate var smokeRoundedCornersAreValid: Bool {
        let expected: CACornerMask = position == .left
            ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        return effect.layer?.maskedCorners == expected
    }

    fileprivate func smokeUpdateHover(pointer: CGPoint, now: TimeInterval, dragging: Bool? = nil) {
        if let dragging { self.dragging = dragging }
        updateHover(pointer: pointer, now: now)
        layoutDocumentView()
    }

    fileprivate var smokeLayoutDescription: String {
        let heights = stack.arrangedSubviews.compactMap { ($0 as? SidebarItemView)?.frame.height }
        return "position=\(position.rawValue) frame=\(frame) natural=\(naturalContentHeight) clip=\(scroll.contentSize) stack=\(stack.frame) rows=\(heights) constraints=\(positionConstraints.map(\.isActive)) cross=\(stackCrossAxisConstraint?.isActive == true)"
    }
}

@MainActor
final class SwitcherPanel: NSPanel {
    private let stack = FlippedStackView()
    private let scroll = NSScrollView()
    private let onActivate: (String) -> Void
    private var displayScreen: NSScreen
    private weak var selectedRow: SwitcherRow?

    init(screen: NSScreen, onActivate: @escaping (String) -> Void) {
        self.displayScreen = screen
        self.onActivate = onActivate
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .aqua)
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(windows: [WindowInfo], selectedIndex: Int) {
        update(windows: windows, selectedIndex: selectedIndex)
        orderFrontRegardless()
        layoutDocumentView()
        revealSelectedRow()
    }

    func update(windows: [WindowInfo], selectedIndex: Int) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        var selectedRow: SwitcherRow?
        for (index, window) in windows.enumerated() {
            let row = SwitcherRow(window: window, selected: index == selectedIndex) { [weak self] in
                self?.onActivate(window.id)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
            if index == selectedIndex { selectedRow = row }
        }

        let area = displayScreen.visibleFrame
        let width = max(320, min(600, area.width - 48))
        let height = min(max(CGFloat(windows.count) * 28 + 16, 44), max(44, area.height - 80))
        setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2,
                        width: width, height: height), display: true)
        layoutDocumentView()
        if let selectedRow {
            self.selectedRow = selectedRow
            revealSelectedRow()
        }
    }

    func move(to screen: NSScreen) {
        displayScreen = screen
    }

    func hideSwitcher() {
        orderOut(nil)
    }

    private func layoutDocumentView() {
        contentView?.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        stack.setFrameSize(NSSize(width: max(scroll.contentSize.width, 1),
                                  height: max(fitting.height, scroll.contentSize.height)))
        stack.layoutSubtreeIfNeeded()
    }

    private func revealSelectedRow() {
        guard let selectedRow else { return }
        selectedRow.scrollToVisible(selectedRow.bounds)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    fileprivate var smokeLayoutIsValid: Bool {
        guard stack.arrangedSubviews.count >= 12,
              stack.arrangedSubviews.allSatisfy({ $0.frame.height <= 28.5 }),
              stack.arrangedSubviews.compactMap({ $0 as? SwitcherRow }).allSatisfy({
                  $0.smokeColumnsAreValid && $0.smokeHitRegionsRouteToRow
                      && $0.smokeHoverAppearanceIsValid
              }),
              let selectedRow else { return false }
        return frame.width <= 600.5
            && frame.height <= displayScreen.visibleFrame.height - 79
            && stack.frame.height > scroll.contentSize.height
            && scroll.contentView.bounds.intersects(selectedRow.convert(selectedRow.bounds, to: scroll.contentView))
    }

    fileprivate var smokeLayoutDescription: String {
        let selectedRect = selectedRow.map { $0.convert($0.bounds, to: scroll.contentView) } ?? .zero
        let rows = stack.arrangedSubviews.compactMap { $0 as? SwitcherRow }
        return "frame=\(frame) stack=\(stack.frame) clip=\(scroll.contentView.bounds) selected=\(selectedRect) columns=\(rows.filter { !$0.smokeColumnsAreValid }.count) hits=\(rows.filter { !$0.smokeHitRegionsRouteToRow }.count) rows=\(stack.arrangedSubviews.map { $0.frame.height })"
    }
}

@MainActor
private final class BadgeLabel: NSTextField {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
}

@MainActor
private final class SidebarItemView: NSView, NSDraggingSource {
    enum Style {
        case group(id: String)
        case window(id: String, groupID: String)

        var id: String {
            switch self {
            case .group(let id), .window(let id, _): id
            }
        }
    }

    fileprivate let style: Style
    fileprivate let iconKey: String?
    fileprivate let badgeKey: String?
    private let titleLabel: NSTextField
    private weak var iconView: NSImageView?
    private weak var badgeLabel: NSTextField?
    private var badgeWidthConstraint: NSLayoutConstraint?
    private var badgeHeightConstraint: NSLayoutConstraint?
    private var badgeTrailingConstraint: NSLayoutConstraint?
    private var badgeTopConstraint: NSLayoutConstraint?
    private let onClick: (() -> Void)?
    private let onDraggingChanged: (Bool) -> Void
    private var mouseDownPoint: NSPoint?
    private var dragging = false
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: NSImage? = nil, iconKey: String? = nil,
         badgeKey: String? = nil, badge: String? = nil,
         style: Style, onClick: (() -> Void)?,
         onDraggingChanged: @escaping (Bool) -> Void) {
        self.style = style
        self.iconKey = iconKey
        self.badgeKey = badgeKey
        self.onClick = onClick
        self.onDraggingChanged = onDraggingChanged
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7
        setAccessibilityRole(onClick == nil ? .group : .button)
        setAccessibilityLabel(title)

        titleLabel.font = switch style {
        case .group: .systemFont(ofSize: 12, weight: .semibold)
        case .window: .systemFont(ofSize: 13, weight: .regular)
        }
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let leading: CGFloat = 4
        var constraints = [
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        if let icon {
            let imageView = NSImageView(image: icon)
            iconView = imageView
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            let badgeLabel = BadgeLabel(labelWithString: "")
            self.badgeLabel = badgeLabel
            badgeLabel.alignment = .center
            badgeLabel.font = .systemFont(ofSize: 8, weight: .semibold)
            badgeLabel.textColor = .white
            badgeLabel.wantsLayer = true
            badgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
            badgeLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badgeLabel)
            let width = badgeLabel.widthAnchor.constraint(equalToConstant: 7)
            let height = badgeLabel.heightAnchor.constraint(equalToConstant: 7)
            let trailing = badgeLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 3)
            let top = badgeLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: -3)
            badgeWidthConstraint = width
            badgeHeightConstraint = height
            badgeTrailingConstraint = trailing
            badgeTopConstraint = top
            constraints += [
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                trailing,
                top,
                width,
                height,
                titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7)
            ]
        } else {
            constraints.append(titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading))
        }
        let height: CGFloat = switch style {
        case .group: 32
        case .window: 25
        }
        constraints.append(heightAnchor.constraint(equalToConstant: height))
        NSLayoutConstraint.activate(constraints)
        setBadge(badge)
    }

    func setIcon(_ icon: NSImage) {
        iconView?.image = icon
    }

    func setBadge(_ value: String?) {
        guard let badgeLabel else { return }
        guard let value else {
            badgeLabel.isHidden = true
            return
        }
        let isDot = value == "•"
        badgeLabel.stringValue = isDot ? "" : value
        let diameter: CGFloat = isDot ? 7 : max(12, min(20, CGFloat(value.count * 5 + 5)))
        badgeWidthConstraint?.constant = diameter
        badgeHeightConstraint?.constant = diameter
        badgeTrailingConstraint?.constant = isDot ? 1 : 3
        badgeTopConstraint?.constant = isDot ? -1 : -3
        badgeLabel.layer?.cornerRadius = diameter / 2
        badgeLabel.isHidden = false
        layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(rect: .zero,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        let pointer = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        setHovered(pointer.map { visibleRect.contains($0) } ?? false)
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    fileprivate var smokeHeightIsValid: Bool {
        let expected: CGFloat = switch style {
        case .group: 32
        case .window: 25
        }
        return abs(frame.height - expected) < 0.5
    }

    fileprivate var smokeHoverAppearanceIsValid: Bool {
        switch style {
        case .group:
            setHovered(true)
            return (layer?.backgroundColor == nil || layer?.backgroundColor == NSColor.clear.cgColor)
                && titleLabel.textColor == .labelColor
        case .window:
            setHovered(true)
            let entered = layer?.backgroundColor == rowHoverColor.cgColor
                && titleLabel.textColor == .white
            setHovered(false)
            return entered && layer?.backgroundColor == NSColor.clear.cgColor
                && titleLabel.textColor == .labelColor
        }
    }

    fileprivate func smokeBadgeIsValid(text: String, diameter: CGFloat) -> Bool {
        guard let badgeLabel, !badgeLabel.isHidden else { return false }
        layoutSubtreeIfNeeded()
        return badgeLabel.stringValue == text
            && badgeLabel.layer?.backgroundColor == NSColor.systemRed.cgColor
            && badgeWidthConstraint?.constant == diameter
            && badgeHeightConstraint?.constant == diameter
            && badgeTrailingConstraint?.constant == 3
            && badgeTopConstraint?.constant == -3
            && abs(badgeLabel.frame.width - diameter) < 0.01
            && abs(badgeLabel.frame.height - diameter) < 0.01
            && abs((badgeLabel.layer?.bounds.width ?? 0) - diameter) < 0.01
            && abs((badgeLabel.layer?.bounds.height ?? 0) - diameter) < 0.01
            && badgeLabel.layer?.cornerRadius == diameter / 2
            && iconView?.image != nil
    }

    fileprivate var smokeDotBadgeIsValid: Bool {
        guard let badgeLabel, !badgeLabel.isHidden else { return false }
        layoutSubtreeIfNeeded()
        return badgeLabel.stringValue.isEmpty
            && badgeWidthConstraint?.constant == 7
            && badgeHeightConstraint?.constant == 7
            && badgeTrailingConstraint?.constant == 1
            && badgeTopConstraint?.constant == -1
            && abs(badgeLabel.frame.width - 7) < 0.01
            && abs(badgeLabel.frame.height - 7) < 0.01
            && abs((badgeLabel.layer?.bounds.width ?? 0) - 7) < 0.01
            && abs((badgeLabel.layer?.bounds.height ?? 0) - 7) < 0.01
            && badgeLabel.layer?.cornerRadius == 3.5
            && iconView?.image != nil
    }

    fileprivate var smokeBadgeIsHidden: Bool { badgeLabel?.isHidden == true }

    fileprivate var smokeBadgeLayoutDescription: String? {
        badgeLabel.map { "frame=\($0.frame) bounds=\($0.layer?.bounds ?? .zero) constraints=\(badgeWidthConstraint?.constant ?? -1)x\(badgeHeightConstraint?.constant ?? -1)" }
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let origin = mouseDownPoint else { return }
        if case .group(let id) = style, id == GroupStore.ungroupedID { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) > 3 else { return }
        dragging = true
        let item = NSPasteboardItem()
        switch style {
        case .group(let id): item.setString(id, forType: .openContextsGroup)
        case .window(let id, _): item.setString(id, forType: .openContextsWindow)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: draggingImage())
        onDraggingChanged(true)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging { onClick?() }
        mouseDownPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        onDraggingChanged(false)
    }

    private func draggingImage() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }

    private func setHovered(_ hovered: Bool) {
        guard case .window = style else { return }
        layer?.backgroundColor = hovered ? rowHoverColor.cgColor : NSColor.clear.cgColor
        titleLabel.textColor = hovered ? .white : .labelColor
    }
}

@MainActor
private final class SwitcherRow: NSButton {
    private let callback: () -> Void
    private let appLabel: NSTextField
    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private let selected: Bool
    private var trackingArea: NSTrackingArea?

    init(window: WindowInfo, selected: Bool, action: @escaping () -> Void) {
        callback = action
        appLabel = NSTextField(labelWithString: window.appName)
        iconView = NSImageView(image: applicationIcon(for: window))
        titleLabel = NSTextField(labelWithString: window.displayTitle)
        self.selected = selected
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = selected ? rowHoverColor.cgColor : NSColor.clear.cgColor
        let textColor = selected ? NSColor.white : NSColor.labelColor
        appLabel.alignment = .right
        appLabel.font = .systemFont(ofSize: 13)
        appLabel.textColor = textColor
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        titleLabel.textColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        iconView.imageScaling = .scaleProportionallyDown
        [appLabel, iconView, titleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            appLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            appLabel.widthAnchor.constraint(equalToConstant: 150),
            iconView.leadingAnchor.constraint(equalTo: appLabel.trailingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        target = self
        self.action = #selector(invoke)
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setAccessibilityLabel("\(window.appName), \(window.displayTitle)")
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(rect: .zero,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        let pointer = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) }
        setHovered(pointer.map { visibleRect.contains($0) } ?? false)
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    fileprivate var smokeColumnsAreValid: Bool {
        appLabel.alignment == .right && appLabel.frame.maxX < iconView.frame.minX
            && iconView.frame.maxX < titleLabel.frame.minX
    }

    fileprivate var smokeHitRegionsRouteToRow: Bool {
        let appPoint = appLabel.convert(NSPoint(x: appLabel.bounds.midX, y: appLabel.bounds.midY), to: superview)
        let iconPoint = iconView.convert(NSPoint(x: iconView.bounds.midX, y: iconView.bounds.midY), to: superview)
        let titlePoint = titleLabel.convert(NSPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY), to: superview)
        return hitTest(appPoint) === self && hitTest(iconPoint) === self && hitTest(titlePoint) === self
    }

    fileprivate var smokeHoverAppearanceIsValid: Bool {
        setHovered(true)
        let entered = layer?.backgroundColor == rowHoverColor.cgColor
            && appLabel.textColor == .white && titleLabel.textColor == .white
        setHovered(false)
        let exited = selected
            ? layer?.backgroundColor == rowHoverColor.cgColor
                && appLabel.textColor == .white && titleLabel.textColor == .white
            : layer?.backgroundColor == NSColor.clear.cgColor
                && appLabel.textColor == .labelColor && titleLabel.textColor == .labelColor
        return entered && exited
    }

    private func setHovered(_ hovered: Bool) {
        let highlighted = selected || hovered
        layer?.backgroundColor = highlighted ? rowHoverColor.cgColor : NSColor.clear.cgColor
        let color: NSColor = highlighted ? .white : .labelColor
        appLabel.textColor = color
        titleLabel.textColor = color
    }

    @objc private func invoke() { callback() }
}

@MainActor
private final class FlippedStackView: NSStackView {
    var onDraggingUpdated: ((NSDraggingInfo) -> NSDragOperation)?
    var onPerformDrag: ((NSDraggingInfo) -> Bool)?
    var onDraggingChanged: ((_ active: Bool, _ restorePreview: Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.openContextsWindow, .openContextsGroup])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.openContextsWindow, .openContextsGroup])
    }

    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingChanged?(true, false)
        return onDraggingUpdated?(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingUpdated?(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onPerformDrag?(sender) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingChanged?(false, true)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDraggingChanged?(false, false)
    }
}

@MainActor
private final class GroupEndDropView: NSView {
    init() {
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 12).isActive = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("移动分组到末尾")
    }

    required init?(coder: NSCoder) { nil }

}

@MainActor
private final class CallbackButton: NSButton {
    private let callback: () -> Void

    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .recessed
        isBordered = false
        alignment = .left
        target = self
        action = #selector(invoke)
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func invoke() { callback() }
}

private extension NSPasteboard.PasteboardType {
    static let openContextsWindow = Self("com.opencontexts.window")
    static let openContextsGroup = Self("com.opencontexts.group")
}

private extension CGRect {
    func approximatelyEquals(_ other: CGRect) -> Bool {
        abs(minX - other.minX) < 0.5 && abs(minY - other.minY) < 0.5
            && abs(width - other.width) < 0.5 && abs(height - other.height) < 0.5
    }
}

@MainActor
private func applicationIcon(for window: WindowInfo) -> NSImage {
    resolvedApplicationIcon(for: window) ?? fallbackApplicationIcon(for: window)
}

private func applicationIconKey(for window: WindowInfo) -> String {
    "\(window.processID):\(window.appID)"
}

@MainActor
private func resolvedApplicationIcon(for window: WindowInfo) -> NSImage? {
    let source = NSRunningApplication(processIdentifier: window.processID)?.icon
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: window.appID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    guard let source else { return nil }
    let icon = (source.copy() as? NSImage) ?? source
    icon.size = NSSize(width: 24, height: 24)
    return icon
}

@MainActor
private func fallbackApplicationIcon(for window: WindowInfo) -> NSImage {
    let source = NSImage(systemSymbolName: "macwindow", accessibilityDescription: window.displayTitle)
        ?? NSImage(size: NSSize(width: 24, height: 24))
    let icon = (source.copy() as? NSImage) ?? source
    icon.size = NSSize(width: 24, height: 24)
    return icon
}

@MainActor
enum PanelSmokeCheck {
    static func run() -> Bool {
        _ = NSApplication.shared
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }

        var windowMoves: [(String, String, String?)] = []
        var groupMoves: [(String, String?)] = []
        let sidebar = SidebarPanel(
            screen: screen,
            onActivate: { _ in },
            onMoveWindow: { windowMoves.append(($0, $1, $2)) },
            onMoveGroup: { groupMoves.append(($0, $1)) },
            onCreateGroup: { _ in },
            onRenameGroup: { _, _ in },
            onDeleteGroup: { _ in }
        )
        sidebar.smokeStopHoverPolling()
        let windows = (0..<200).map {
            WindowInfo(id: "smoke-\($0)", appID: "smoke", appName: "Smoke",
                       title: "Window \($0)", processID: ProcessInfo.processInfo.processIdentifier)
        }
        let groups = [WindowGroup(id: GroupStore.ungroupedID, name: "未分组")]
        let area = screen.visibleFrame
        var measuredHeights: [Int: CGFloat] = [:]
        for count in [0, 1, 3] {
            sidebar.update(groups: groups,
                           windowsByGroup: [GroupStore.ungroupedID: Array(windows.prefix(count))],
                           alwaysVisible: true, fullscreen: false, position: .right)
            sidebar.contentView?.layoutSubtreeIfNeeded()
            measuredHeights[count] = sidebar.frame.height
            guard naturalHeightIsValid(sidebar, in: area), sidebar.smokeRowsAreCompact,
                  sidebar.smokeRowHoverAppearanceIsValid, sidebar.smokePositionLayoutIsValid else {
                sidebar.close()
                return fail("sidebar natural height mismatch count=\(count): \(sidebar.smokeLayoutDescription)")
            }
        }
        guard let zeroHeight = measuredHeights[0], let oneHeight = measuredHeights[1],
              let threeHeight = measuredHeights[3], zeroHeight < oneHeight, oneHeight < threeHeight else {
            sidebar.close()
            return fail("sidebar natural heights did not grow: \(measuredHeights)")
        }

        for (value, text, diameter) in [
            ("1" as String?, "1", CGFloat(12)),
            ("•", "", CGFloat(7)),
            ("12", "12", CGFloat(15)),
            (nil, "", CGFloat(0)),
            ("•", "", CGFloat(7))
        ] {
            sidebar.smokeApplyBadges(value.map { ["smoke": $0] } ?? [:])
            sidebar.contentView?.layoutSubtreeIfNeeded()
            let valid = value == nil
                ? sidebar.smokeBadgesAreHidden
                : diameter == 7
                    ? sidebar.smokeDotBadgesAreValid
                    : sidebar.smokeBadgesAreValid(text: text, diameter: diameter)
            guard valid else {
                sidebar.close()
                return fail("sidebar badge renderer mismatch value=\(value ?? "nil") \(sidebar.smokeBadgeLayoutDescription)")
            }
        }

        sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: windows],
                       alwaysVisible: true, fullscreen: false, position: .right)
        sidebar.contentView?.layoutSubtreeIfNeeded()
        guard abs(sidebar.frame.height - area.height) < 1, sidebar.smokeHasOverflow,
              sidebar.smokeScrollLastWindowIntoView() else {
            sidebar.close()
            return fail("sidebar overflow mismatch: \(sidebar.smokeLayoutDescription) expectedArea=\(area)")
        }

        sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: [windows[0]]],
                       alwaysVisible: true, fullscreen: false, position: .right)
        sidebar.contentView?.layoutSubtreeIfNeeded()
        guard abs(sidebar.frame.height - oneHeight) < 1 else {
            sidebar.close()
            return fail("sidebar did not shrink after overflow: one=\(oneHeight) \(sidebar.smokeLayoutDescription)")
        }

        for position in SidebarPosition.allCases {
            sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: [windows[0]]],
                           alwaysVisible: false, fullscreen: false, position: position)
            var frames = sidebar.smokeSidebarFrames
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 8),
                  abs(sidebar.frame.height - oneHeight) < 1, sidebar.smokeIsHidden,
                  sidebar.smokeRoundedCornersAreValid else {
                sidebar.close()
                return fail("sidebar collapsed mismatch: \(sidebar.smokeLayoutDescription) expectedArea=\(area)")
            }
            let edgePoint = CGPoint(x: frames.edge.midX, y: frames.edge.midY)
            let insidePoint = CGPoint(x: frames.expanded.midX, y: frames.expanded.midY)
            let outsidePoint = CGPoint(x: frames.expanded.midX, y: frames.expanded.maxY + 40)
            sidebar.smokeUpdateHover(pointer: edgePoint, now: 0)
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 188),
                  abs(sidebar.frame.height - oneHeight) < 1, !sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar hover mismatch: \(sidebar.smokeLayoutDescription) expectedArea=\(area)")
            }
            sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: [windows[0]]],
                           alwaysVisible: false, fullscreen: false, position: position)
            sidebar.smokeUpdateHover(pointer: insidePoint, now: 0.05)
            sidebar.smokeUpdateHover(pointer: outsidePoint, now: 0.1)
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 188),
                  !sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar collapsed before delay: \(sidebar.smokeLayoutDescription)")
            }
            sidebar.smokeUpdateHover(pointer: outsidePoint, now: 0.23)
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 8),
                  sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar did not collapse after leave: \(sidebar.smokeLayoutDescription)")
            }
            sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: [windows[0]]],
                           alwaysVisible: false, fullscreen: false, position: position)
            guard sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar refresh exposed collapsed panel: \(sidebar.smokeLayoutDescription)")
            }

            sidebar.smokeUpdateHover(pointer: edgePoint, now: 0.3)
            sidebar.smokeUpdateHover(pointer: outsidePoint, now: 0.4, dragging: true)
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 188),
                  !sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar collapsed during drag: \(sidebar.smokeLayoutDescription)")
            }
            sidebar.smokeUpdateHover(pointer: outsidePoint, now: 0.5, dragging: false)
            sidebar.smokeUpdateHover(pointer: outsidePoint, now: 0.63)
            guard edgeFrame(sidebar.frame, in: area, position: position, width: 8),
                  sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar did not collapse after drag: \(sidebar.smokeLayoutDescription)")
            }

            sidebar.update(groups: groups, windowsByGroup: [GroupStore.ungroupedID: [windows[0]]],
                           alwaysVisible: true, fullscreen: true, position: position)
            frames = sidebar.smokeSidebarFrames
            guard edgeFrame(sidebar.frame, in: screen.frame, position: position, width: 8),
                  sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar fullscreen collapse mismatch: \(sidebar.smokeLayoutDescription) expectedArea=\(screen.frame)")
            }
            sidebar.smokeUpdateHover(pointer: CGPoint(x: frames.edge.midX, y: frames.edge.midY), now: 1)
            guard edgeFrame(sidebar.frame, in: screen.frame, position: position, width: 188),
                  !sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar fullscreen hover mismatch: \(sidebar.smokeLayoutDescription) expectedArea=\(screen.frame)")
            }
            let fullscreenOutside = CGPoint(x: frames.expanded.midX, y: frames.expanded.maxY + 40)
            sidebar.smokeUpdateHover(pointer: fullscreenOutside, now: 1.1)
            sidebar.smokeUpdateHover(pointer: fullscreenOutside, now: 1.23)
            guard edgeFrame(sidebar.frame, in: screen.frame, position: position, width: 8),
                  sidebar.smokeIsHidden else {
                sidebar.close()
                return fail("sidebar fullscreen did not collapse after leave: \(sidebar.smokeLayoutDescription)")
            }
        }

        let firstGroupID = "smoke-group-1"
        let secondGroupID = "smoke-group-2"
        let dragGroups = [
            WindowGroup(id: GroupStore.ungroupedID, name: "未分组"),
            WindowGroup(id: firstGroupID, name: "Group 1"),
            WindowGroup(id: secondGroupID, name: "Group 2")
        ]
        let originalWindows = [
            GroupStore.ungroupedID: [windows[0]],
            firstGroupID: [windows[1], windows[2]],
            secondGroupID: [windows[3]]
        ]
        sidebar.update(groups: dragGroups, windowsByGroup: originalWindows,
                       alwaysVisible: true, fullscreen: false, position: .right)
        sidebar.contentView?.layoutSubtreeIfNeeded()
        let originalOrder = sidebar.smokeRowOrder
        let sourceIdentity = sidebar.smokeWindowIdentity(windows[1].id)
        sidebar.smokeBeginDrag()
        sidebar.smokePreviewWindow(windows[1].id, groupID: secondGroupID,
                                   beforeWindowID: windows[3].id)
        let previewOrder = sidebar.smokeRowOrder
        let selfHitWasStable = sidebar.smokeWindowSelfHitKeepsPreview(
            windows[1].id, groupID: secondGroupID
        )
        sidebar.smokePreviewWindow(windows[1].id, groupID: secondGroupID,
                                   beforeWindowID: windows[3].id)
        guard previewOrder != originalOrder, sidebar.smokeRowOrder == previewOrder,
              selfHitWasStable,
              sidebar.smokeWindowIdentity(windows[1].id) == sourceIdentity,
              windowMoves.isEmpty, groupMoves.isEmpty else {
            sidebar.close()
            return fail("sidebar live preview changed identity or invoked callbacks")
        }
        sidebar.smokeDestinationExited()
        guard sidebar.smokeRowOrder == originalOrder, sidebar.smokeIsDragging,
              sidebar.smokeWindowIdentity(windows[1].id) == sourceIdentity else {
            sidebar.close()
            return fail("sidebar destination exit ended source drag or replaced its view")
        }
        sidebar.smokePreviewWindow(windows[1].id, groupID: secondGroupID,
                                   beforeWindowID: windows[3].id)
        sidebar.smokeCommitPreview()
        guard windowMoves.count == 1,
              windowMoves[0].0 == windows[1].id,
              windowMoves[0].1 == secondGroupID,
              windowMoves[0].2 == windows[3].id else {
            sidebar.close()
            return fail("sidebar window drop callback mismatch: \(windowMoves)")
        }
        let refreshedWindows = [
            GroupStore.ungroupedID: [windows[0]],
            firstGroupID: [windows[2]],
            secondGroupID: [windows[1], windows[3]]
        ]
        sidebar.update(groups: dragGroups, windowsByGroup: refreshedWindows,
                       alwaysVisible: true, fullscreen: false, position: .right)
        sidebar.smokeEndDrag()
        guard sidebar.smokeRowOrder == [
            "g:\(GroupStore.ungroupedID)", "w:\(windows[0].id)",
            "g:\(firstGroupID)", "w:\(windows[2].id)",
            "g:\(secondGroupID)", "w:\(windows[1].id)", "w:\(windows[3].id)"
        ] else {
            sidebar.close()
            return fail("sidebar pending refresh was not applied after drop")
        }
        sidebar.smokeBeginDrag()
        sidebar.smokePreviewGroup(secondGroupID, beforeGroupID: firstGroupID)
        let groupPreviewOrder = sidebar.smokeRowOrder
        sidebar.smokeCommitPreview()
        sidebar.smokeEndDrag()
        let secondIndex = groupPreviewOrder.firstIndex(of: "g:\(secondGroupID)") ?? .max
        let firstIndex = groupPreviewOrder.firstIndex(of: "g:\(firstGroupID)") ?? -1
        guard groupPreviewOrder.first == "g:\(GroupStore.ungroupedID)",
              secondIndex < firstIndex,
              groupMoves.count == 1, groupMoves[0].0 == secondGroupID,
              groupMoves[0].1 == firstGroupID else {
            sidebar.close()
            return fail("sidebar group preview or callback mismatch")
        }
        sidebar.smokeBeginDrag()
        sidebar.smokeDestinationEntered()
        sidebar.smokeEndDrag()
        guard !sidebar.smokeIsDragging else {
            sidebar.close()
            return fail("sidebar remained in dragging state after source cancellation")
        }

        let switcher = SwitcherPanel(screen: screen, onActivate: { _ in })
        let switcherWindows = windows
        switcher.show(windows: switcherWindows, selectedIndex: switcherWindows.count - 1)
        switcher.contentView?.layoutSubtreeIfNeeded()
        let valid = switcher.smokeLayoutIsValid
        switcher.hideSwitcher()
        switcher.close()
        sidebar.close()
        return valid ? true : fail("switcher layout mismatch: \(switcher.smokeLayoutDescription)")
    }

    private static func edgeFrame(_ frame: NSRect, in area: NSRect,
                                  position: SidebarPosition, width: CGFloat) -> Bool {
        let centered = abs(frame.midY - area.midY) < 1
        switch position {
        case .left: return centered && abs(frame.minX - area.minX) < 1 && abs(frame.width - width) < 1
        case .right: return centered && abs(frame.maxX - area.maxX) < 1 && abs(frame.width - width) < 1
        }
    }

    private static func naturalHeightIsValid(_ sidebar: SidebarPanel, in area: NSRect) -> Bool {
        abs(sidebar.frame.height - min(sidebar.smokeNaturalContentHeight, area.height)) < 1
            && abs(sidebar.frame.midY - area.midY) < 1
    }

    private static func fail(_ message: String) -> Bool {
        FileHandle.standardError.write(Data("PanelSmokeCheck failed: \(message)\n".utf8))
        return false
    }
}
