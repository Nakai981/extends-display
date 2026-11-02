import UIKit

protocol DesktopContent: AnyObject {
    func pointerClick(at point: CGPoint, secondary: Bool)
    func pointerScroll(at point: CGPoint, delta: CGPoint)
    func insertText(_ text: String)
}

final class DesktopController: UIViewController, UIGestureRecognizerDelegate {
    let external: Bool
    private let wallpaper = WallpaperView()
    private let menuMaterial = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let dockMaterial = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let menu = UIStackView()
    private let dock = UIStackView()
    private let dockScroll = UIScrollView()
    private let canvas = UIView()
    private let desktopIcons = DesktopIconsView()
    private let activeApp = UILabel()
    private let cursor = UIImageView(image: UIImage(systemName: "cursorarrow"))
    private var frames: [UUID: DesktopWindow] = [:]
    private var clockTimer: Timer?
    private let clock = UILabel()
    private var pointer = CGPoint(x: 300, y: 200)
    private var dragID: UUID?
    private var resizeID: UUID?
    private var interactionMoved = false
    private var panel: DesktopPanel?
    private var commandMenu: DesktopMenuView?
    private var lastRecords: [UUID: WindowRecord] = [:]
    private var lastOrder: [UUID] = []
    private var dockSignature = ""
    private var compactMenu: Bool?
    private var dockVisible = true
    private var observation: NSObjectProtocol?
    private var displayObservation: NSObjectProtocol?
    private var appearanceObservation: NSObjectProtocol?
    var hasOverlay: Bool { panel != nil || commandMenu != nil }
    init(external: Bool) { self.external = external; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = DesktopPreferences.shared.interfaceStyle
        view.addSubview(wallpaper); view.addSubview(canvas); canvas.addSubview(desktopIcons)
        desktopIcons.onOpen = { Workspace.shared.open(.files, url: $0.absoluteString) }
        desktopIcons.onContext = { [weak self] url, point in guard let self else { return }; self.showFileMenu(url, at: self.desktopIcons.convert(point, to: self.view)) }
        menu.axis = .horizontal; menu.spacing = 6; menu.alignment = .center
        menu.backgroundColor = .clear
        menu.isLayoutMarginsRelativeArrangement = true
        menu.layoutMargins = UIEdgeInsets(top: 0, left: 18, bottom: 0, right: 18)
        activeApp.font = .systemFont(ofSize: 13, weight: .semibold); activeApp.textColor = .label
        clock.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); clock.textColor = .label
        view.addSubview(menuMaterial); view.addSubview(menu)
        dock.axis = .horizontal; dock.spacing = 8; dock.alignment = .center
        dock.backgroundColor = UIColor(white: 0.1, alpha: 0.8)
        dock.layer.cornerRadius = 20; dock.isLayoutMarginsRelativeArrangement = true
        dock.layoutMargins = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        dockScroll.showsHorizontalScrollIndicator = false; dockScroll.backgroundColor = .clear
        dockScroll.layer.cornerRadius = 22; dock.backgroundColor = .clear
        dockScroll.layer.borderWidth = 1; dockScroll.layer.borderColor = DesktopStyle.border.cgColor
        dockMaterial.layer.cornerRadius = 22; dockMaterial.clipsToBounds = true
        dockScroll.addSubview(dock); view.addSubview(dockMaterial); view.addSubview(dockScroll)
        cursor.tintColor = .white; cursor.layer.shadowOpacity = 0.7; cursor.layer.shadowRadius = 2
        cursor.isUserInteractionEnabled = false; cursor.contentMode = .scaleAspectFit
        view.addSubview(cursor); cursor.isHidden = !external
        observation = NotificationCenter.default.addObserver(forName: .workspaceChanged, object: nil, queue: .main) { [weak self] _ in self?.render() }
        displayObservation = NotificationCenter.default.addObserver(forName: .displayChanged, object: nil, queue: .main) { [weak self] _ in self?.render() }
        appearanceObservation = NotificationCenter.default.addObserver(forName: .appearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.applyAppearance() }
        let secondary = UITapGestureRecognizer(target: self, action: #selector(nativeContext(_:))); secondary.buttonMaskRequired = .secondary; secondary.cancelsTouchesInView = false; secondary.delegate = self; view.addGestureRecognizer(secondary)
        view.addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(nativeHover(_:))))
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.updateClock() }
        updateClock(); render()
    }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) }; if let displayObservation { NotificationCenter.default.removeObserver(displayObservation) }; if let appearanceObservation { NotificationCenter.default.removeObserver(appearanceObservation) }; clockTimer?.invalidate() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); wallpaper.frame = view.bounds
        let top = view.safeAreaInsets.top
        if compactMenu != (view.bounds.width < 700) { compactMenu = view.bounds.width < 700; buildMenuBar() }
        menu.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: 36); menuMaterial.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top + 36)
        let dockHeight = DesktopPreferences.shared.dockSize + 20
        let reserved: CGFloat = DesktopPreferences.shared.dockAutoHide ? 8 : dockHeight + 20
        canvas.frame = CGRect(x: 0, y: top + 36, width: view.bounds.width, height: max(0, view.bounds.height - top - 36 - reserved - view.safeAreaInsets.bottom))
        desktopIcons.frame = canvas.bounds
        let size = dock.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let dockWidth = min(size.width, view.bounds.width - 24)
        dockScroll.transform = .identity; dockMaterial.transform = .identity
        dockScroll.frame = CGRect(x: (view.bounds.width - dockWidth) / 2, y: view.bounds.height - dockHeight - 12 - view.safeAreaInsets.bottom, width: dockWidth, height: dockHeight)
        dockMaterial.frame = dockScroll.frame
        dock.frame = CGRect(x: 0, y: 0, width: size.width, height: dockHeight); dockScroll.contentSize = dock.bounds.size
        panel?.frame = view.bounds; commandMenu?.frame = view.bounds
        updateDockVisibility(animated: false)
        layoutWindows(); positionCursor()
    }
    private func updateClock() { let formatter = DateFormatter(); formatter.dateFormat = compactMenu == true ? "HH:mm" : "EEE d MMM  HH:mm"; clock.text = formatter.string(from: Date()) }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) == true { applyAppearance() }
    }
    func render() {
        guard isViewLoaded else { return }
        if !external && Workspace.shared.externalDesktop != nil {
            suspend(); return
        }
        let records = Workspace.shared.windows
        for id in Array(frames.keys) where !records.contains(where: { $0.id == id }) {
            if let frame = frames.removeValue(forKey: id) {
                detach(frame); frame.removeFromSuperview()
            }
        }
        for record in records {
            let frame: DesktopWindow
            if let existing = frames[record.id] { frame = existing }
            else {
                guard !record.minimized else { continue }
                frame = DesktopWindow(record: record)
                frames[record.id] = frame
                if frame.content.parent != nil { frame.content.willMove(toParent: nil); frame.content.view.removeFromSuperview(); frame.content.removeFromParent() }
                addChild(frame.content); canvas.addSubview(frame)
                frame.attachContent(); frame.content.didMove(toParent: self)
                frame.constrainFrame = { [weak self] rect in self?.constrained(rect) ?? rect }
            }
            frame.isHidden = record.minimized || Workspace.shared.desktopRevealed
            (frame.content as? BrowserController)?.setDesktopVisible(!frame.isHidden)
            (frame.content as? PhotosController)?.setDesktopVisible(!frame.isHidden)
            frame.update(record, focused: Workspace.shared.focusedID == record.id)
            if lastRecords[record.id]?.frame != record.frame || lastRecords[record.id]?.maximized != record.maximized { view.setNeedsLayout() }
        }
        let order = records.map(\.id)
        if order != lastOrder { for id in order { if let frame = frames[id] { canvas.bringSubviewToFront(frame) } }; lastOrder = order }
        lastRecords = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        updateDock(records)
        activeApp.text = Workspace.shared.desktopRevealed ? "Desktop" : records.first(where: { $0.id == Workspace.shared.focusedID })?.kind.title ?? "ExtendDesk"
    }
    func suspend() {
        guard !frames.isEmpty || hasOverlay || dragID != nil || resizeID != nil else { return }
        pointerUp(); dismissPanel()
        for frame in frames.values { detach(frame); frame.removeFromSuperview() }
        frames.removeAll(); lastRecords.removeAll(); lastOrder.removeAll()
    }
    private func detach(_ frame: DesktopWindow) {
        guard frame.content.parent === self else { return }
        (frame.content as? BrowserController)?.setDesktopVisible(false)
        (frame.content as? PhotosController)?.setDesktopVisible(false)
        frame.content.willMove(toParent: nil); frame.content.view.removeFromSuperview(); frame.content.removeFromParent()
    }
    private func updateDock(_ records: [WindowRecord]) {
        let running = AppKind.allCases.map { kind in kind.rawValue + (records.contains(where: { $0.kind == kind }) ? ":on" : ":off") }.joined(separator: "|")
        let pinned = Workspace.shared.bookmarks.map { $0.id.uuidString + $0.title }.joined(separator: "|")
        let minimized = records.filter(\.minimized).map { $0.id.uuidString + $0.title }.joined(separator: "|")
        let signature = running + pinned + minimized + String(Double(DesktopPreferences.shared.dockSize))
        guard signature != dockSignature else { return }; dockSignature = signature
        dock.arrangedSubviews.forEach { dock.removeArrangedSubview($0); $0.removeFromSuperview() }
        dock.addArrangedSubview(dockButton("square.grid.2x2.fill", label: "Applications", tint: .systemPurple, running: false) { [weak self] in self?.showLauncher() })
        for kind in AppKind.allCases {
            let button = dockButton(kind.symbol, label: kind.title, tint: kind.tint, running: records.contains(where: { $0.kind == kind })) { Workspace.shared.activate(kind) }
            button.accessibilityIdentifier = "dock." + kind.rawValue
            dock.addArrangedSubview(button)
        }
        for bookmark in Workspace.shared.bookmarks {
            dock.addArrangedSubview(dockButton("globe", label: bookmark.title, tint: .systemIndigo, running: false) { Workspace.shared.open(.browser, url: bookmark.url) })
        }
        for record in records where record.minimized {
            dock.addArrangedSubview(dockButton("rectangle.on.rectangle", label: "Restore " + record.title, tint: record.kind.tint, running: true) { Workspace.shared.focus(record.id) })
        }
        view.setNeedsLayout()
    }
    private func dockButton(_ symbol: String, label: String, tint: UIColor, running: Bool, action: @escaping () -> Void) -> UIButton {
        let button = actionButton(symbol, title: nil, action: action)
        var config = button.configuration; config?.background.backgroundColor = tint; config?.background.cornerRadius = 12
        config?.baseForegroundColor = .white
        config?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        button.configuration = config; button.accessibilityLabel = label
        let size = DesktopPreferences.shared.dockSize
        button.widthAnchor.constraint(equalToConstant: size).isActive = true; button.heightAnchor.constraint(equalToConstant: size).isActive = true
        button.addInteraction(UIToolTipInteraction(defaultToolTip: label))
        if running { let dot = UIView(frame: CGRect(x: size / 2 - 2, y: size + 3, width: 4, height: 4)); dot.layer.cornerRadius = 2; dot.backgroundColor = .label; dot.isUserInteractionEnabled = false; button.addSubview(dot) }
        return button
    }
    private func layoutWindows() {
        for record in Workspace.shared.windows {
            frames[record.id]?.frame = record.maximized ? canvas.bounds.insetBy(dx: 6, dy: 6) : constrained(record.frame)
        }
    }
    private func constrained(_ rect: CGRect) -> CGRect {
        WindowGeometry.constrain(rect, to: canvas.bounds)
    }
    func movePointer(_ delta: CGPoint) {
        pointer.x = min(max(0, pointer.x + delta.x), view.bounds.width - 1)
        pointer.y = min(max(0, pointer.y + delta.y), view.bounds.height - 1)
        if let id = dragID, let window = frames[id] {
            if delta != .zero { interactionMoved = true }
            window.frame = constrained(window.frame.offsetBy(dx: delta.x, dy: delta.y))
            Workspace.shared.update(id, notify: false) { $0.setFrame(window.frame); $0.maximized = false }
        }
        if let id = resizeID, let window = frames[id] {
            if delta != .zero { interactionMoved = true }
            var rect = window.frame; rect.size.width += delta.x; rect.size.height += delta.y
            window.frame = constrained(rect)
            Workspace.shared.update(id, notify: false) { $0.setFrame(window.frame); $0.maximized = false }
        }
        positionCursor()
        commandMenu?.hover(at: pointer); updateDockVisibility(animated: true)
    }
    private func positionCursor() { cursor.frame = CGRect(x: pointer.x, y: pointer.y, width: 23, height: 28); view.bringSubviewToFront(cursor) }
    func pointerDown() {
        interactionMoved = false
        guard !hasOverlay else { return }
        if dockVisible && dockScroll.frame.contains(pointer) { return }
        guard let window = windowAtPointer() else { return }
        let point = view.convert(pointer, to: window)
        Workspace.shared.focus(window.id)
        if point.y < DesktopStyle.headerHeight, point.x > 94 { dragID = window.id }
        else if point.x > window.bounds.width - 28, point.y > window.bounds.height - 28 { resizeID = window.id }
    }
    @discardableResult func pointerUp() -> Bool {
        let shouldClick = !interactionMoved
        if interactionMoved { Workspace.shared.changed() }
        dragID = nil; resizeID = nil; interactionMoved = false
        return shouldClick
    }
    func click(secondary: Bool = false) {
        if let commandMenu { commandMenu.click(at: pointer); return }
        if let panel { panel.click(at: pointer); return }
        if secondary { showContext(at: pointer); return }
        if dockVisible && dockScroll.frame.contains(pointer) { activateDockButton(at: pointer); return }
        if let window = windowAtPointer() {
            Workspace.shared.focus(window.id)
            let local = view.convert(pointer, to: window)
            var hit = window.hitTest(local, with: nil)
            while let candidate = hit, candidate !== window.content.view {
                if let control = candidate as? UIButton { control.sendActions(for: .touchUpInside); return }
                hit = candidate.superview
            }
            if local.y >= DesktopStyle.headerHeight {
                let point = view.convert(pointer, to: window.content.view)
                (window.content as? DesktopContent)?.pointerClick(at: point, secondary: secondary)
            }
        } else {
            let local = view.convert(pointer, to: desktopIcons)
            if canvas.frame.contains(pointer), desktopIcons.item(at: local) != nil { desktopIcons.click(at: local); return }
            var hit = view.hitTest(pointer, with: nil)
            while let candidate = hit, candidate !== view {
                if let button = candidate as? UIButton { button.sendActions(for: .touchUpInside); return }
                hit = candidate.superview
            }
        }
    }
    func scroll(_ delta: CGPoint) {
        if let commandMenu { commandMenu.scroll(by: delta); return }
        if let panel { panel.scroll(by: delta); return }
        if dockScroll.frame.contains(pointer) { dockScroll.contentOffset.x = min(max(0, dockScroll.contentOffset.x + delta.y + delta.x), max(0, dockScroll.contentSize.width - dockScroll.bounds.width)); return }
        guard let window = windowAtPointer() else { return }
        (window.content as? DesktopContent)?.pointerScroll(at: view.convert(pointer, to: window.content.view), delta: delta)
    }
    func type(_ text: String) {
        if commandMenu != nil { if text == "\n" { commandMenu?.openSelected() }; if text == "\u{1B}" { dismissPanel() }; return }
        if let panel { panel.insertText(text); return }
        guard let content = activeWindow?.content as? DesktopContent else { return }
        content.insertText(text)
    }
    func interactOnDevice() {
        guard let browser = activeWindow?.content as? BrowserController else { return }
        browser.interactOnDevice()
    }
    func setPointer(normalized point: CGPoint) {
        movePointer(CGPoint(x: point.x * view.bounds.width - pointer.x, y: point.y * view.bounds.height - pointer.y))
    }
    func snapshot(completion: @escaping (UIImage?) -> Void) {
        view.layoutIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else { completion(nil); return }
        let scale = min(1, min(1280 / view.bounds.width, 720 / view.bounds.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale), format: format)
        let image = renderer.image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            if view.isHidden { view.layer.render(in: context.cgContext) }
            else { view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) }
        }
        completion(image)
    }
    private func windowAtPointer() -> DesktopWindow? {
        let point = view.convert(pointer, to: canvas)
        return Workspace.shared.windows.reversed().compactMap { frames[$0.id] }.first { !$0.isHidden && $0.frame.contains(point) }
    }
    func snap(right: Bool) {
        placeFocusedWindow(right ? .right : .left)
    }
    func showLauncher() {
        showPanel(.launcher)
    }
    func showWindows() {
        showPanel(.windows)
    }
    func showSearch() {
        showPanel(.search)
    }
    func dismissPanel() { panel?.removeFromSuperview(); panel = nil; commandMenu?.removeFromSuperview(); commandMenu = nil }
    private func showPanel(_ mode: DesktopPanel.Mode) {
        dismissPanel()
        let panel = DesktopPanel(mode: mode); self.panel = panel; panel.frame = view.bounds
        panel.onDismiss = { [weak self] in self?.dismissPanel() }
        panel.onQuery = { [weak self, weak panel] query in if let panel { self?.populate(panel, query: query) } }
        view.addSubview(panel); populate(panel, query: ""); positionCursor()
    }
    private func populate(_ panel: DesktopPanel, query: String) {
        var entries: [DesktopEntry] = []
        if panel.mode == .windows {
            entries = Workspace.shared.windows.reversed().prefix(60).enumerated().map { index, record in
                var preview: UIImage?
                if index < 12, let frame = frames[record.id], !frame.isHidden, frame.bounds.width > 0 {
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let size = CGSize(width: 220, height: 110)
                    preview = UIGraphicsImageRenderer(size: size, format: format).image { context in context.cgContext.scaleBy(x: size.width / frame.bounds.width, y: size.height / frame.bounds.height); frame.layer.render(in: context.cgContext) }
                }
                return DesktopEntry(title: record.title, subtitle: record.minimized ? "Minimized" : record.kind.title, symbol: record.kind.symbol, tint: record.kind.tint, image: preview, action: { Workspace.shared.focus(record.id) })
            }
        } else {
            entries = AppKind.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }.map { kind in
                DesktopEntry(title: kind.title, subtitle: "Application", symbol: kind.symbol, tint: kind.tint, action: { Workspace.shared.activate(kind) })
            }
            entries += Workspace.shared.bookmarks.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query) }.map { item in
                DesktopEntry(title: item.title, subtitle: "Web app", symbol: "globe", tint: .systemIndigo, action: { Workspace.shared.open(.browser, url: item.url) })
            }
            if panel.mode == .search, !query.isEmpty, let url = Address.resolve(query) {
                entries.append(DesktopEntry(title: "Open or search: " + query, subtitle: url.host ?? "Web", symbol: "magnifyingglass", tint: DesktopStyle.accent, action: { Workspace.shared.open(.browser, url: url.absoluteString) }))
                let fixed = entries
                DesktopFileIndex.shared.search(query) { [weak self, weak panel] urls in
                    guard let self, let panel, self.panel === panel, panel.query == query else { return }
                    panel.setEntries(fixed + urls.map { url in DesktopEntry(title: url.lastPathComponent, subtitle: "Files · " + url.deletingLastPathComponent().lastPathComponent, symbol: "doc", tint: .systemBlue, action: { Workspace.shared.open(.files, url: url.absoluteString) }) })
                }
            }
        }
        panel.setEntries(entries)
    }
}

enum WindowGeometry {
    static func constrain(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let availableWidth = max(1, bounds.width), availableHeight = max(1, bounds.height)
        let width = min(availableWidth, max(min(340, availableWidth), rect.width))
        let height = min(availableHeight, max(min(220, availableHeight), rect.height))
        return CGRect(x: min(max(0, rect.minX), max(0, availableWidth - width)), y: min(max(0, rect.minY), max(0, availableHeight - height)), width: width, height: height)
    }
}

final class DesktopWindow: UIView {
    let id: UUID
    let content: UIViewController
    private let title = UILabel()
    private let header = UIView()
    private let surface = UIView()
    private let appIcon = UIImageView()
    private var startingFrame = CGRect.zero
    var constrainFrame: ((CGRect) -> CGRect)?
    private var displayedTitle = ""
    private var wasFocused = false
    init(record: WindowRecord) {
        id = record.id
        content = Workspace.shared.content(for: record)
        super.init(frame: record.frame)
        backgroundColor = .clear; layer.cornerRadius = 12
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.3; layer.shadowRadius = 16; layer.shadowOffset = CGSize(width: 0, height: 10)
        surface.backgroundColor = .secondarySystemBackground; surface.layer.cornerRadius = 12; surface.clipsToBounds = true
        surface.layer.borderWidth = 1; addSubview(surface)
        header.backgroundColor = DesktopStyle.surface; surface.addSubview(header)
        let actions: [(UIColor, String, () -> Void)] = [
            (.systemRed, "Close", { Workspace.shared.close(record.id) }),
            (.systemYellow, "Minimize", { Workspace.shared.update(record.id) { $0.minimized = true } }),
            (.systemGreen, "Maximize", { Workspace.shared.update(record.id) { $0.maximized.toggle() } })]
        for (index, item) in actions.enumerated() {
            let button = UIButton(type: .custom)
            button.frame = CGRect(x: 6 + index * 27, y: 3, width: 27, height: 30)
            let dot = UIView(frame: CGRect(x: 7, y: 8, width: 13, height: 13)); dot.backgroundColor = item.0; dot.layer.cornerRadius = 6.5; dot.isUserInteractionEnabled = false; button.addSubview(dot)
            button.accessibilityLabel = item.1; button.addAction(UIAction { _ in item.2() }, for: .touchUpInside)
            header.addSubview(button)
        }
        title.textColor = .label; title.font = .systemFont(ofSize: 12, weight: .medium); title.textAlignment = .center
        title.isUserInteractionEnabled = false; header.addSubview(title)
        appIcon.image = UIImage(systemName: record.kind.symbol); appIcon.tintColor = record.kind.tint; appIcon.contentMode = .scaleAspectFit; header.addSubview(appIcon)
        header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(maximize)); doubleTap.numberOfTapsRequired = 2; header.addGestureRecognizer(doubleTap)
        let handle = UIView(); handle.tag = 90; handle.backgroundColor = .clear
        let grip = UIView(frame: CGRect(x: 8, y: 20, width: 16, height: 3)); grip.backgroundColor = .systemGray; grip.layer.cornerRadius = 1.5; grip.isUserInteractionEnabled = false; handle.addSubview(grip)
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:)))); addSubview(handle)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func attachContent() { surface.insertSubview(content.view, belowSubview: header) }
    override func layoutSubviews() {
        super.layoutSubviews(); surface.frame = bounds; header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: DesktopStyle.headerHeight)
        title.frame = CGRect(x: 116, y: 0, width: max(0, bounds.width - 232), height: DesktopStyle.headerHeight)
        appIcon.frame = CGRect(x: 96, y: 10, width: 16, height: 16)
        content.view.frame = CGRect(x: 0, y: DesktopStyle.headerHeight, width: bounds.width, height: max(0, bounds.height - DesktopStyle.headerHeight))
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
        viewWithTag(90)?.frame = CGRect(x: bounds.width - 30, y: bounds.height - 30, width: 30, height: 30)
        if let handle = viewWithTag(90) { bringSubviewToFront(handle) }
    }
    func update(_ record: WindowRecord, focused: Bool) {
        if displayedTitle != record.title { displayedTitle = record.title; title.text = record.title }
        if wasFocused != focused || surface.layer.borderColor == nil {
            wasFocused = focused; surface.layer.borderColor = (focused ? DesktopStyle.accent.withAlphaComponent(0.7) : DesktopStyle.border).resolvedColor(with: traitCollection).cgColor
            layer.shadowOpacity = focused ? 0.45 : 0.22
        }
    }
    func refreshAppearance() { wasFocused.toggle(); if let record = Workspace.shared.windows.first(where: { $0.id == id }) { update(record, focused: Workspace.shared.focusedID == id) }; header.backgroundColor = DesktopStyle.surface }
    @objc private func maximize() { Workspace.shared.update(id) { $0.maximized.toggle() } }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { startingFrame = frame; Workspace.shared.focus(id) }
        let delta = gesture.translation(in: superview)
        let proposed = startingFrame.offsetBy(dx: delta.x, dy: delta.y)
        frame = constrainFrame?(proposed) ?? proposed
        Workspace.shared.update(id, notify: gesture.state == .ended || gesture.state == .cancelled) { $0.setFrame(frame); $0.maximized = false }
        if gesture.state == .ended || gesture.state == .cancelled { Workspace.shared.changed() }
    }
    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { startingFrame = frame }
        let delta = gesture.translation(in: superview)
        let proposed = CGRect(origin: startingFrame.origin, size: CGSize(width: max(300, startingFrame.width + delta.x), height: max(220, startingFrame.height + delta.y)))
        frame = constrainFrame?(proposed) ?? proposed
        Workspace.shared.update(id, notify: gesture.state == .ended || gesture.state == .cancelled) { $0.setFrame(frame); $0.maximized = false }
        if gesture.state == .ended || gesture.state == .cancelled { Workspace.shared.changed() }
    }
}

func actionButton(_ symbol: String, title: String?, action: @escaping () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol); configuration.title = title
    configuration.imagePadding = 6; configuration.baseForegroundColor = .label
    let button = UIButton(configuration: configuration)
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
}

private enum DesktopMenuSection: String { case application, file, edit, view, window, help, control }

extension DesktopController {
    private var activeWindow: DesktopWindow? {
        guard !Workspace.shared.desktopRevealed, let id = Workspace.shared.focusedID, let frame = frames[id], !frame.isHidden else { return nil }
        return frame
    }
    private func buildMenuBar() {
        menu.arrangedSubviews.forEach { menu.removeArrangedSubview($0); $0.removeFromSuperview() }
        let app = menuButton("", symbol: "square.stack.3d.up.fill", section: .application); app.accessibilityLabel = "ExtendDesk menu"; menu.addArrangedSubview(app)
        if compactMenu != true {
            activeApp.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); menu.addArrangedSubview(activeApp)
            for section in [DesktopMenuSection.file, .edit, .view, .window, .help] { menu.addArrangedSubview(menuButton(section.rawValue.capitalized, section: section)) }
        } else { menu.addArrangedSubview(menuButton("Window", section: .window)) }
        menu.addArrangedSubview(UIView())
        menu.addArrangedSubview(actionButton("magnifyingglass", title: nil) { [weak self] in self?.showSearch() })
        menu.addArrangedSubview(menuButton("", symbol: "slider.horizontal.3", section: .control))
        menu.addArrangedSubview(clock); updateClock()
    }
    private func menuButton(_ text: String, symbol: String? = nil, section: DesktopMenuSection) -> UIButton {
        var config = UIButton.Configuration.plain(); config.title = text.isEmpty ? nil : text; config.image = symbol.flatMap(UIImage.init(systemName:)); config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var attributes = $0; attributes.font = .systemFont(ofSize: 13); return attributes }
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }; self.showMenu(self.items(for: section), at: button.convert(CGPoint(x: 0, y: button.bounds.height + 4), to: self.view))
        }, for: .touchUpInside)
        return button
    }
    private func showMenu(_ items: [DesktopMenuItem], at point: CGPoint) {
        dismissPanel(); let overlay = DesktopMenuView(items: items, origin: point); commandMenu = overlay
        overlay.frame = view.bounds; overlay.onDismiss = { [weak self] in self?.dismissPanel() }; view.addSubview(overlay); positionCursor()
    }
    private func items(for section: DesktopMenuSection) -> [DesktopMenuItem] {
        let hasWindow = activeWindow != nil, browser = activeWindow?.content is BrowserController
        switch section {
        case .application:
            return [DesktopMenuItem(title: "About ExtendDesk", symbol: "info.circle", action: { [weak self] in self?.showInformation("ExtendDesk", message: "A desktop workspace powered by your iPhone or iPad.\nUse File, View and Window to manage your apps.") }),
                    DesktopMenuItem(title: "System Settings…", symbol: "gearshape", shortcut: "⌘,", action: { Workspace.shared.activate(.settings) }),
                    DesktopMenuItem(title: "Applications", symbol: "square.grid.2x2", action: { [weak self] in self?.showLauncher() }),
                    DesktopMenuItem(title: "File Menu", symbol: "doc", action: { [weak self] in guard let self else { return }; self.showMenu(self.items(for: .file), at: CGPoint(x: 16, y: 42)) }),
                    DesktopMenuItem(title: "View Menu", symbol: "eye", action: { [weak self] in guard let self else { return }; self.showMenu(self.items(for: .view), at: CGPoint(x: 16, y: 42)) }),
                    DesktopMenuItem(title: "Show Desktop", symbol: "menubar.dock.rectangle", shortcut: "⌃⌘D", checked: Workspace.shared.desktopRevealed, action: { Workspace.shared.toggleDesktop() })]
        case .file:
            return [DesktopMenuItem(title: "New Browser Window", symbol: "globe", shortcut: "⌘N", action: { Workspace.shared.open(.browser) }),
                    DesktopMenuItem(title: "New Tab", symbol: "plus.square", shortcut: "⌘T", action: { [weak self] in self?.performBrowserCommand(.newTab) }),
                    DesktopMenuItem(title: "New Note", symbol: "square.and.pencil", action: { Workspace.shared.open(.notes) }),
                    DesktopMenuItem(title: "New Desktop Folder…", symbol: "folder.badge.plus", action: { [weak self] in self?.newDesktopFolder() }),
                    DesktopMenuItem(title: "Open Desktop Folder", symbol: "folder", action: { Workspace.shared.open(.files, url: Workspace.desktopFolder.absoluteString) }),
                    DesktopMenuItem(title: "Open Photos", symbol: "photo.on.rectangle", action: { Workspace.shared.activate(.photos) }),
                    DesktopMenuItem(title: "Downloads", symbol: "arrow.down.circle", action: { DownloadStore.shared.openDownloads() }),
                    DesktopMenuItem(title: "Close Tab", symbol: "xmark", shortcut: "⌘W", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.closeTab) }),
                    DesktopMenuItem(title: "Close Window", symbol: "xmark.rectangle", shortcut: "⇧⌘W", enabled: hasWindow, action: { [weak self] in self?.closeFocusedWindow() })]
        case .edit:
            return [DesktopMenuItem(title: "Find in Page…", symbol: "magnifyingglass", shortcut: "⌘F", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.find) }),
                    DesktopMenuItem(title: "Copy Page Address", symbol: "link", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.copyURL) }),
                    DesktopMenuItem(title: "Paste Text", symbol: "doc.on.clipboard", shortcut: "⌘V", enabled: hasWindow, action: { [weak self] in if let text = UIPasteboard.general.string { self?.type(text) } }),
                    DesktopMenuItem(title: "Use Keyboard on Device", symbol: "keyboard", enabled: browser, action: { [weak self] in self?.interactOnDevice() })]
        case .view:
            return [DesktopMenuItem(title: "Back", symbol: "chevron.left", shortcut: "⌘[", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.back) }),
                    DesktopMenuItem(title: "Forward", symbol: "chevron.right", shortcut: "⌘]", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.forward) }),
                    DesktopMenuItem(title: "Pin Current Website", symbol: "pin", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.pin) }),
                    DesktopMenuItem(title: "Zoom In", symbol: "plus.magnifyingglass", shortcut: "⌘+", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.zoomIn) }),
                    DesktopMenuItem(title: "Zoom Out", symbol: "minus.magnifyingglass", shortcut: "⌘−", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.zoomOut) }),
                    DesktopMenuItem(title: "Actual Size", symbol: "1.magnifyingglass", shortcut: "⌘0", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.actualSize) }),
                    DesktopMenuItem(title: "Reload Page", symbol: "arrow.clockwise", shortcut: "⌘R", enabled: browser, action: { [weak self] in self?.performBrowserCommand(.reload) }),
                    DesktopMenuItem(title: "All Windows", symbol: "rectangle.3.group", shortcut: "⌘↑", action: { [weak self] in self?.showWindows() }),
                    DesktopMenuItem(title: "Show Desktop", symbol: "menubar.dock.rectangle", checked: Workspace.shared.desktopRevealed, action: { Workspace.shared.toggleDesktop() }),
                    DesktopMenuItem(title: "Automatically Hide Dock", symbol: "dock.rectangle", checked: DesktopPreferences.shared.dockAutoHide, action: { DesktopPreferences.shared.dockAutoHide.toggle() })]
        case .window:
            var rows = WindowPlacement.allCases.map { placement in DesktopMenuItem(title: placement.title, symbol: "rectangle.split.2x2", enabled: hasWindow, action: { [weak self] in self?.placeFocusedWindow(placement) }) }
            rows += [DesktopMenuItem(title: "Minimize", symbol: "minus", shortcut: "⌘M", enabled: hasWindow, action: { [weak self] in self?.minimizeFocusedWindow() }),
                    DesktopMenuItem(title: "Next Window", symbol: "rectangle.on.rectangle", shortcut: "⌘`", enabled: Workspace.shared.windows.count > 1, action: { Workspace.shared.cycleWindow() }),
                     DesktopMenuItem(title: "All Windows", symbol: "rectangle.3.group", action: { [weak self] in self?.showWindows() })]
            return rows
        case .help:
            return [DesktopMenuItem(title: "Keyboard Shortcuts", symbol: "keyboard", action: { [weak self] in self?.showInformation("Keyboard Shortcuts", message: "⌘N New browser · ⌘T New tab\n⌘F Find in page · ⌘R Reload\n⌘+ / ⌘− / ⌘0 Zoom\n⌘M Minimize · ⌘W Close tab\n⇧⌘W Close window\n⌃Space Search · ⌘↑ All windows\n⌃Tab Next tab · ⌘` Next window\n⌘, Settings · ⌃⌘D Show desktop\n\nUse your device’s input field for text. Web on device handles sites requiring direct interaction.") }),
                    DesktopMenuItem(title: "Connection Guide", symbol: "display", action: { [weak self] in self?.showInformation("Connect a Display", message: "Connect a video-capable USB-C cable or HDMI adapter. Pair a mouse and keyboard if needed. Use the device trackpad, or Preview when no external screen is attached.") })]
        case .control:
            var rows = DesktopAppearance.allCases.map { style in DesktopMenuItem(title: style.title + " Appearance", symbol: style == .dark ? "moon.fill" : "sun.max", checked: DesktopPreferences.shared.appearance == style, action: { DesktopPreferences.shared.appearance = style }) }
            rows += [DesktopMenuItem(title: "Automatically Hide Dock", symbol: "dock.rectangle", checked: DesktopPreferences.shared.dockAutoHide, action: { DesktopPreferences.shared.dockAutoHide.toggle() }),
                     DesktopMenuItem(title: "Reduce Motion", symbol: "figure.walk", checked: DesktopPreferences.shared.reduceMotion, action: { DesktopPreferences.shared.reduceMotion.toggle() }),
                     DesktopMenuItem(title: "System Settings…", symbol: "gearshape", action: { Workspace.shared.activate(.settings) })]
            return rows
        }
    }
    private func applyAppearance() {
        overrideUserInterfaceStyle = DesktopPreferences.shared.interfaceStyle
        dockSignature = ""; dockScroll.layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor
        for frame in frames.values { frame.refreshAppearance() }
        panel?.refreshAppearance(); commandMenu?.refreshAppearance(); desktopIcons.setNeedsDisplay(); render(); view.setNeedsLayout()
    }
    private func updateDockVisibility(animated: Bool) {
        let show = !DesktopPreferences.shared.dockAutoHide || pointer.y >= view.bounds.height - DesktopPreferences.shared.dockSize - 44 || hasOverlay
        guard show != dockVisible || !animated else { return }; dockVisible = show
        let changes = { [self] in
            let transform = show ? CGAffineTransform.identity : CGAffineTransform(translationX: 0, y: dockScroll.bounds.height + 24)
            dockScroll.transform = transform; dockMaterial.transform = transform
        }
        if animated && !DesktopPreferences.shared.effectiveReduceMotion { UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes) }
        else { changes() }
    }
    @objc private func nativeContext(_ gesture: UITapGestureRecognizer) {
        guard !external else { return }; pointer = gesture.location(in: view)
        if let window = windowAtPointer(), view.convert(pointer, to: window).y >= DesktopStyle.headerHeight, !(dockVisible && dockScroll.frame.contains(pointer)) { return }
        showContext(at: pointer)
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UITapGestureRecognizer else { return true }
        let point = gestureRecognizer.location(in: view)
        if dockVisible && dockScroll.frame.contains(point) { return true }
        if let window = windowAtPoint(point) { return view.convert(point, to: window).y < DesktopStyle.headerHeight }
        return desktopIcons.item(at: view.convert(point, to: desktopIcons)) == nil
    }
    @objc private func nativeHover(_ gesture: UIHoverGestureRecognizer) {
        guard !external else { return }; pointer = gesture.location(in: view); commandMenu?.hover(at: pointer); updateDockVisibility(animated: true)
    }
    private func showContext(at point: CGPoint) {
        pointer = point
        if dockVisible && dockScroll.frame.contains(point) {
            if let kind = dockKind(at: point) {
                showMenu([DesktopMenuItem(title: "New " + kind.title + " Window", symbol: "plus", action: { Workspace.shared.open(kind) }), DesktopMenuItem(title: "Show " + kind.title, symbol: kind.symbol, action: { Workspace.shared.activate(kind) }), DesktopMenuItem(title: "All Windows", symbol: "rectangle.3.group", action: { [weak self] in self?.showWindows() })], at: point)
            }
            return
        }
        if let window = windowAtPointer() {
            Workspace.shared.focus(window.id)
            let local = view.convert(point, to: window)
            if local.y < DesktopStyle.headerHeight { showMenu(items(for: .window), at: point) }
            else { (window.content as? DesktopContent)?.pointerClick(at: view.convert(point, to: window.content.view), secondary: true) }
            return
        }
        if let url = desktopIcons.item(at: view.convert(point, to: desktopIcons)) { showFileMenu(url, at: point); return }
        showMenu([DesktopMenuItem(title: "New Folder…", symbol: "folder.badge.plus", action: { [weak self] in self?.newDesktopFolder() }), DesktopMenuItem(title: "Open Desktop Folder", symbol: "folder", action: { Workspace.shared.open(.files, url: Workspace.desktopFolder.absoluteString) }), DesktopMenuItem(title: "Applications", symbol: "square.grid.2x2", action: { [weak self] in self?.showLauncher() }), DesktopMenuItem(title: "Change Wallpaper…", symbol: "photo", action: { Workspace.shared.activate(.settings) })], at: point)
    }
    private func windowAtPoint(_ point: CGPoint) -> DesktopWindow? {
        let local = view.convert(point, to: canvas)
        return Workspace.shared.windows.reversed().compactMap { frames[$0.id] }.first { !$0.isHidden && $0.frame.contains(local) }
    }
    private func dockKind(at point: CGPoint) -> AppKind? {
        var hit = dockScroll.hitTest(view.convert(point, to: dockScroll), with: nil)
        while let candidate = hit, candidate !== dockScroll {
            if let identifier = candidate.accessibilityIdentifier, identifier.hasPrefix("dock.") { return AppKind(rawValue: String(identifier.dropFirst(5))) }; hit = candidate.superview
        }
        return nil
    }
    private func activateDockButton(at point: CGPoint) {
        var hit = dockScroll.hitTest(view.convert(point, to: dockScroll), with: nil)
        while let candidate = hit, candidate !== dockScroll {
            if let button = candidate as? UIButton { button.sendActions(for: .touchUpInside); return }; hit = candidate.superview
        }
    }
    func showControlCenter() { showMenu(items(for: .control), at: CGPoint(x: view.bounds.width - 312, y: 42 + view.safeAreaInsets.top)) }
    private func showFileMenu(_ url: URL, at point: CGPoint) {
        var rows = [DesktopMenuItem(title: "Open", symbol: "arrow.up.forward.square", action: { Workspace.shared.open(.files, url: url.absoluteString) }), DesktopMenuItem(title: "Reveal in Files", symbol: "folder", action: { Workspace.shared.open(.files, url: url.deletingLastPathComponent().absoluteString) })]
        if FileOperations.contains(url, in: Workspace.desktopFolder), url != Workspace.desktopFolder {
            rows.append(DesktopMenuItem(title: "Rename…", symbol: "pencil", action: { [weak self] in self?.askName("Rename", initial: url.lastPathComponent) { [weak self = self] name in self?.runFileOperation { _ = try FileOperations.rename(url, to: name) } } }))
        }
        showMenu(rows, at: point)
    }
    func navigateOverlay(_ delta: Int) { if let commandMenu { commandMenu.moveSelection(delta) } else { panel?.moveSelection(delta) } }
    func activateOverlaySelection() { if let commandMenu { commandMenu.openSelected() } else { panel?.openSelected() } }
    func escape() { if hasOverlay { dismissPanel() } else { (activeWindow?.content as? BrowserController)?.dismissTransientUI() } }
    @discardableResult func performBrowserCommand(_ command: BrowserCommand) -> Bool {
        if let browser = activeWindow?.content as? BrowserController { browser.perform(command); return true }
        if command == .newTab { Workspace.shared.open(.browser); return true }
        return false
    }
    func minimizeFocusedWindow() { guard let id = activeWindow?.id else { return }; Workspace.shared.update(id) { $0.minimized = true } }
    func closeFocusedWindow() { if let id = activeWindow?.id { Workspace.shared.close(id) } }
    func placeFocusedWindow(_ placement: WindowPlacement) {
        guard let id = activeWindow?.id else { return }
        Workspace.shared.update(id) { record in
            if placement == .restore { if let previous = record.restoreFrame { record.setFrame(constrained(previous)) }; record.restoreFrame = nil; record.maximized = false; return }
            if record.restoreFrame == nil { record.restoreFrame = record.frame }
            record.maximized = false; record.setFrame(constrained(placement.frame(in: canvas.bounds, current: record.frame)))
        }
    }
    private var phonePresenter: UIViewController {
        var controller = Workspace.shared.localDesktop?.parent ?? self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
    private func showInformation(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); phonePresenter.present(alert, animated: true)
    }
    private func askName(_ title: String, initial: String = "", action: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert); alert.addTextField { $0.text = initial }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard FileOperations.validName(name) else { self?.showInformation("Invalid name", message: "Choose a name without slash, colon or dot-only components."); return }; action(name)
        }); phonePresenter.present(alert, animated: true)
    }
    private func newDesktopFolder() { askName("New Desktop Folder", initial: "Untitled Folder") { [weak self] name in self?.runFileOperation { try FileManager.default.createDirectory(at: Workspace.desktopFolder.appendingPathComponent(name), withIntermediateDirectories: false) } } }
    private func runFileOperation(_ operation: @escaping () throws -> Void) {
        FileOperations.queue.async { [weak self] in
            do { try operation(); DispatchQueue.main.async { NotificationCenter.default.post(name: .filesChanged, object: nil) } }
            catch { DispatchQueue.main.async { [weak self = self] in self?.showInformation("File operation failed", message: error.localizedDescription) } }
        }
    }
}
