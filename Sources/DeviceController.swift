import UIKit

final class DeviceController: UIViewController, UIGestureRecognizerDelegate, UITextFieldDelegate {
    private let desktop = DesktopController(external: false)
    private let controls = UIStackView()
    private let controlsScroll = UIScrollView()
    private let status = UILabel()
    private let input = UITextField()
    private let pad = UIView()
    private var showDesktop = false
    private var observers: [NSObjectProtocol] = []
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidLoad() {
        super.viewDidLoad(); overrideUserInterfaceStyle = DesktopPreferences.shared.interfaceStyle; view.backgroundColor = .systemGroupedBackground
        MouseBridge.shared.start()
        addChild(desktop); view.addSubview(desktop.view); desktop.didMove(toParent: self)
        Workspace.shared.localDesktop = desktop
        controls.axis = .vertical; controls.spacing = 14; controls.translatesAutoresizingMaskIntoConstraints = false
        controlsScroll.translatesAutoresizingMaskIntoConstraints = false; controlsScroll.keyboardDismissMode = .interactive
        view.addSubview(controlsScroll); controlsScroll.addSubview(controls)
        status.textColor = .label; status.font = .systemFont(ofSize: 20, weight: .semibold); status.numberOfLines = 0
        controls.addArrangedSubview(status)
        let instruction = UILabel(); instruction.text = "One finger: move • Tap: click • Two fingers: scroll\nHold + move: drag/resize • Two-finger tap: context menu"
        instruction.numberOfLines = 0; instruction.font = .systemFont(ofSize: 12); instruction.textColor = .secondaryLabel
        controls.addArrangedSubview(instruction)
        pad.backgroundColor = .secondarySystemGroupedBackground; pad.layer.cornerRadius = 24; pad.layer.borderWidth = 1; pad.layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor
        pad.accessibilityLabel = "Desktop trackpad"
        controls.addArrangedSubview(pad)
        let icon = UIImageView(image: UIImage(systemName: "hand.draw")); icon.tintColor = .systemGray; icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false; pad.addSubview(icon)
        NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: pad.centerXAnchor), icon.centerYAnchor.constraint(equalTo: pad.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 54), icon.heightAnchor.constraint(equalToConstant: 54)])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(move(_:))); pan.maximumNumberOfTouches = 2; pan.delegate = self; pad.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(click)); pad.addGestureRecognizer(tap)
        let secondary = UITapGestureRecognizer(target: self, action: #selector(rightClick)); secondary.numberOfTouchesRequired = 2; pad.addGestureRecognizer(secondary); tap.require(toFail: secondary)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hold(_:))); hold.minimumPressDuration = 0.3; hold.delegate = self; pad.addGestureRecognizer(hold)
        let row = UIStackView(); row.distribution = .fillEqually; row.spacing = 4
        row.addArrangedSubview(actionButton("square.grid.2x2", title: "Apps") { Workspace.shared.activeDesktop?.showLauncher() })
        row.addArrangedSubview(actionButton("rectangle.3.group", title: "Windows") { Workspace.shared.activeDesktop?.showWindows() })
        row.addArrangedSubview(actionButton("magnifyingglass", title: "Go") { Workspace.shared.activeDesktop?.showSearch() })
        controls.addArrangedSubview(row)
        input.placeholder = "Type text, then Send"; input.borderStyle = .roundedRect; input.autocorrectionType = .no
        input.delegate = self; input.returnKeyType = .send; input.autocapitalizationType = .none
        let inputRow = UIStackView(arrangedSubviews: [input, actionButton("paperplane.fill", title: "Send") { [weak self] in self?.send() }]); inputRow.spacing = 8
        controls.addArrangedSubview(inputRow)
        let tools = UIStackView(); tools.distribution = .fillEqually
        tools.addArrangedSubview(actionButton("delete.left", title: nil) { Workspace.shared.activeDesktop?.type("\u{8}") })
        tools.addArrangedSubview(actionButton("return", title: nil) { Workspace.shared.activeDesktop?.type("\n") })
        tools.addArrangedSubview(actionButton("rectangle.lefthalf.inset.filled", title: nil) { Workspace.shared.activeDesktop?.snap(right: false) })
        tools.addArrangedSubview(actionButton("rectangle.righthalf.inset.filled", title: nil) { Workspace.shared.activeDesktop?.snap(right: true) })
        tools.addArrangedSubview(actionButton("display", title: "Preview") { [weak self] in self?.togglePreview() })
        controls.addArrangedSubview(tools)
        let more = UIStackView(); more.distribution = .fillEqually
        more.addArrangedSubview(actionButton("hand.tap", title: "Web on device") { Workspace.shared.activeDesktop?.interactOnDevice() })
        more.addArrangedSubview(actionButton("antenna.radiowaves.left.and.right", title: "Share LAN") { [weak self] in self?.shareLAN() })
        controls.addArrangedSubview(more)
        let workspaceTools = UIStackView(); workspaceTools.distribution = .fillEqually
        workspaceTools.addArrangedSubview(actionButton("menubar.dock.rectangle", title: "Desktop") { Workspace.shared.toggleDesktop() })
        workspaceTools.addArrangedSubview(actionButton("slider.horizontal.3", title: "Controls") { Workspace.shared.activeDesktop?.showControlCenter() })
        workspaceTools.addArrangedSubview(actionButton("gearshape", title: "Settings") { Workspace.shared.activate(.settings) })
        controls.addArrangedSubview(workspaceTools)
        NSLayoutConstraint.activate([
            controlsScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), controlsScroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), controlsScroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor), controlsScroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            controls.topAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.topAnchor, constant: 20),
            controls.leadingAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: controlsScroll.contentLayoutGuide.bottomAnchor, constant: -16),
            controls.widthAnchor.constraint(equalTo: controlsScroll.frameLayoutGuide.widthAnchor, constant: -40),
            pad.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)])
        let fillHeight = controls.heightAnchor.constraint(greaterThanOrEqualTo: controlsScroll.frameLayoutGuide.heightAnchor, constant: -36); fillHeight.priority = .defaultLow; fillHeight.isActive = true
        observers.append(NotificationCenter.default.addObserver(forName: .displayChanged, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(NotificationCenter.default.addObserver(forName: .appearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.overrideUserInterfaceStyle = DesktopPreferences.shared.interfaceStyle; if let self { pad.layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor } })
        refresh(); becomeFirstResponder()
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); desktop.view.frame = view.bounds; controls.spacing = view.bounds.width > view.bounds.height ? 8 : 14 }
    private func refresh() {
        if Workspace.shared.externalDesktop != nil { showDesktop = false; view.viewWithTag(999)?.removeFromSuperview() }
        status.text = Workspace.shared.externalDesktop == nil ? "ExtendDesk · No external display" : "ExtendDesk · Display connected"
        controlsScroll.isHidden = showDesktop; desktop.view.isHidden = !showDesktop
        if showDesktop { addBackButton() }
    }
    private func togglePreview() {
        if let external = Workspace.shared.externalDesktop {
            external.snapshot { [weak self] image in
                guard let self, let image else { return }
                let controller = SnapshotController(image: image)
                present(UINavigationController(rootViewController: controller), animated: true)
            }
        } else { showDesktop.toggle(); refresh() }
    }
    private func shareLAN() {
        let server = DesktopSharing.shared
        let alert = UIAlertController(title: "LAN screen sharing", message: server.running ? server.connectionInfo : "Start a local browser viewer. Keep this app in the foreground. Use only a trusted private network; traffic is not encrypted.", preferredStyle: .alert)
        if server.running {
            alert.addAction(UIAlertAction(title: "Stop sharing", style: .destructive) { _ in server.stop() })
            alert.addAction(UIAlertAction(title: "Copy address", style: .default) { _ in UIPasteboard.general.string = server.connectionInfo })
        } else {
            alert.addAction(UIAlertAction(title: "Start", style: .default) { [weak self] _ in
                server.start { result in
                    let message: String
                    switch result { case .success: message = server.connectionInfo; case .failure(let error): message = error.localizedDescription }
                    let info = UIAlertController(title: "LAN sharing", message: message, preferredStyle: .alert)
                    info.addAction(UIAlertAction(title: "OK", style: .default)); self?.present(info, animated: true)
                }
            })
        }; alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); present(alert, animated: true)
    }
    private func addBackButton() {
        guard view.viewWithTag(999) == nil else { return }
        let back = actionButton("arrow.uturn.backward.circle.fill", title: "Trackpad") { [weak self] in
            self?.view.viewWithTag(999)?.removeFromSuperview(); self?.showDesktop = false; self?.refresh()
        }
        back.tag = 999; back.backgroundColor = .black; back.layer.cornerRadius = 16
        back.frame = CGRect(x: 12, y: view.bounds.height - 120, width: 150, height: 40)
        back.autoresizingMask = [.flexibleTopMargin]; view.addSubview(back)
    }
    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { Workspace.shared.activeDesktop?.pointerDown() }
        if gesture.state == .ended || gesture.state == .cancelled { Workspace.shared.activeDesktop?.pointerUp() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer) || (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
    }
    @objc private func move(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: pad); gesture.setTranslation(.zero, in: pad)
        if gesture.numberOfTouches == 2 { Workspace.shared.activeDesktop?.scroll(CGPoint(x: -delta.x, y: -delta.y)) }
        else { Workspace.shared.activeDesktop?.movePointer(CGPoint(x: delta.x * Workspace.shared.pointerSpeed, y: delta.y * Workspace.shared.pointerSpeed)) }
    }
    @objc private func click() { Workspace.shared.activeDesktop?.click() }
    @objc private func rightClick() { Workspace.shared.activeDesktop?.click(secondary: true) }
    private func send() { if let text = input.text, !text.isEmpty { Workspace.shared.activeDesktop?.type(text); input.text = "" } }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { send(); return false }
    override var keyCommands: [UIKeyCommand]? {
        var commands = [UIKeyCommand(title: "New Browser", action: #selector(newBrowser), input: "n", modifierFlags: .command),
         UIKeyCommand(title: "Search", action: #selector(search), input: "l", modifierFlags: .command),
         UIKeyCommand(title: "Close Tab or Window", action: #selector(closeWindow), input: "w", modifierFlags: .command),
         UIKeyCommand(title: "Close Window", action: #selector(closeWholeWindow), input: "w", modifierFlags: [.command, .shift]),
         UIKeyCommand(title: "Next Tab", action: #selector(nextTab), input: "\t", modifierFlags: .control),
         UIKeyCommand(title: "Previous Tab", action: #selector(previousTab), input: "\t", modifierFlags: [.control, .shift]),
         UIKeyCommand(title: "Next Window", action: #selector(nextWindow), input: "`", modifierFlags: .command),
         UIKeyCommand(title: "Minimize", action: #selector(minimize), input: "m", modifierFlags: .command),
         UIKeyCommand(title: "Settings", action: #selector(settings), input: ",", modifierFlags: .command),
         UIKeyCommand(title: "Show Desktop", action: #selector(showDesktopShortcut), input: "d", modifierFlags: [.command, .control]),
         UIKeyCommand(title: "All Windows", action: #selector(windows), input: UIKeyCommand.inputUpArrow, modifierFlags: .command),
         UIKeyCommand(title: "Smart Search", action: #selector(search), input: " ", modifierFlags: .control),
         UIKeyCommand(title: "Dismiss Panel", action: #selector(dismissPanel), input: UIKeyCommand.inputEscape, modifierFlags: [])]
        for (title, key) in [("New Tab", "t"), ("Find in Page", "f"), ("Reload", "r"), ("Zoom In", "+"), ("Zoom Out", "-"), ("Actual Size", "0"), ("Back", "["), ("Forward", "]")] {
            commands.append(UIKeyCommand(title: title, action: #selector(browserShortcut(_:)), input: key, modifierFlags: .command))
        }
        if Workspace.shared.activeDesktop?.hasOverlay == true {
            commands += [UIKeyCommand(title: "Previous Item", action: #selector(previousItem), input: UIKeyCommand.inputUpArrow, modifierFlags: []), UIKeyCommand(title: "Next Item", action: #selector(nextItem), input: UIKeyCommand.inputDownArrow, modifierFlags: []), UIKeyCommand(title: "Open Selected Item", action: #selector(openItem), input: "\r", modifierFlags: [])]
        }
        return commands
    }
    @objc private func newBrowser() { Workspace.shared.open(.browser) }
    @objc private func search() { Workspace.shared.activeDesktop?.showSearch() }
    @objc private func closeWindow() { if Workspace.shared.activeDesktop?.performBrowserCommand(.closeTab) != true { Workspace.shared.activeDesktop?.closeFocusedWindow() } }
    @objc private func closeWholeWindow() { Workspace.shared.activeDesktop?.closeFocusedWindow() }
    @objc private func windows() { Workspace.shared.activeDesktop?.showWindows() }
    @objc private func nextWindow() { Workspace.shared.cycleWindow() }
    @objc private func nextTab() { if Workspace.shared.activeDesktop?.performBrowserCommand(.nextTab) != true { Workspace.shared.cycleWindow() } }
    @objc private func previousTab() { if Workspace.shared.activeDesktop?.performBrowserCommand(.previousTab) != true { Workspace.shared.cycleWindow() } }
    @objc private func minimize() { Workspace.shared.activeDesktop?.minimizeFocusedWindow() }
    @objc private func settings() { Workspace.shared.activate(.settings) }
    @objc private func showDesktopShortcut() { Workspace.shared.toggleDesktop() }
    @objc private func previousItem() { Workspace.shared.activeDesktop?.navigateOverlay(-1) }
    @objc private func nextItem() { Workspace.shared.activeDesktop?.navigateOverlay(1) }
    @objc private func openItem() { Workspace.shared.activeDesktop?.activateOverlaySelection() }
    @objc private func browserShortcut(_ command: UIKeyCommand) {
        let mapping: [String: BrowserCommand] = ["t": .newTab, "f": .find, "r": .reload, "+": .zoomIn, "-": .zoomOut, "0": .actualSize, "[": .back, "]": .forward]
        if let key = command.input, let action = mapping[key] { Workspace.shared.activeDesktop?.performBrowserCommand(action) }
    }
    @objc private func dismissPanel() { Workspace.shared.activeDesktop?.escape() }
}

final class SnapshotController: UIViewController {
    private let image: UIImage
    init(image: UIImage) { self.image = image; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "External desktop snapshot"; view.backgroundColor = .black
        let imageView = UIImageView(image: image); imageView.contentMode = .scaleAspectFit; imageView.frame = view.bounds; imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(imageView)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }
    @objc private func done() { dismiss(animated: true) }
}
