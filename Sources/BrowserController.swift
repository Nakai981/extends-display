import UIKit
import WebKit

enum BrowserCommand: Equatable {
    case newTab, closeTab, nextTab, previousTab, reload, back, forward, find
    case zoomIn, zoomOut, actualSize, pin, downloads, copyURL
}

final class BrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate, DesktopContent {
    let id: UUID
    private var session: BrowserSession
    private struct LiveTab {
        let web: WKWebView
        var observation: NSKeyValueObservation?
        var lastUsed = Date()
    }
    private var liveTabs: [UUID: LiveTab] = [:]
    private let address = UITextField()
    private let toolbar = UIStackView()
    private let tabScroll = UIScrollView()
    private let tabRow = UIStackView()
    private let bookmarkScroll = UIScrollView()
    private let bookmarkRow = UIStackView()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let findBar = UIStackView()
    private let findField = UITextField()
    private let findStatus = UILabel()
    private var findVisible = false
    private var findInputFocused = false
    private var replaceFindInput = false
    private var findWork: DispatchWorkItem?
    private var findGeneration = UUID()
    private var findCountCache: (tab: UUID, term: String, count: Int, capped: Bool)?
    private let status = UILabel()
    private let webHost = UIView()
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private let reloadButton = UIButton(type: .system)
    private var downloadButton: UIButton!
    private var addButton: UIButton!
    private var observers: [NSObjectProtocol] = []
    private var sessionSave: DispatchWorkItem?
    private var bookmarksSignature: [UUID] = []
    private var deviceSession: WebInteractionController?
    private var downloadsPanel: DownloadCenterView?
    private var desktopVisible = true
    var web: WKWebView { webView(for: session.selectedID) }

    init(id: UUID, url: String?) {
        self.id = id
        if let data = UserDefaults.standard.data(forKey: "browser.session.\(id)"), var restored = try? JSONDecoder().decode(BrowserSession.self, from: data) {
            restored.normalize(); session = restored
        } else { session = BrowserSession(url: url ?? "https://www.apple.com") }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = DesktopStyle.surface
        tabScroll.showsHorizontalScrollIndicator = false
        tabRow.axis = .horizontal; tabRow.spacing = 4; tabScroll.addSubview(tabRow); view.addSubview(tabScroll)
        addButton = actionButton("plus", title: nil) { [weak self] in self?.newTab() }
        addButton.accessibilityLabel = "New tab"; view.addSubview(addButton)
        toolbar.axis = .horizontal; toolbar.spacing = 1; toolbar.alignment = .center
        configure(back, symbol: "chevron.left", label: "Back") { [weak self] in self?.web.goBack() }
        configure(forward, symbol: "chevron.right", label: "Forward") { [weak self] in self?.web.goForward() }
        configure(reloadButton, symbol: "arrow.clockwise", label: "Reload") { [weak self] in
            guard let self else { return }; web.isLoading ? web.stopLoading() : web.reload()
        }
        [back, forward, reloadButton].forEach { toolbar.addArrangedSubview($0); $0.widthAnchor.constraint(equalToConstant: 30).isActive = true }
        address.borderStyle = .roundedRect; address.autocapitalizationType = .none; address.autocorrectionType = .no
        address.keyboardType = .URL; address.returnKeyType = .go; address.delegate = self; address.placeholder = "Search or enter address"
        address.font = .systemFont(ofSize: 13); toolbar.addArrangedSubview(address)
        let pin = actionButton("star", title: nil) { [weak self] in self?.perform(.pin) }
        pin.accessibilityLabel = "Pin website"; pin.widthAnchor.constraint(equalToConstant: 30).isActive = true; toolbar.addArrangedSubview(pin)
        downloadButton = actionButton("arrow.down.circle", title: nil) { [weak self] in self?.showDownloads() }
        downloadButton.accessibilityLabel = "Downloads"; downloadButton.widthAnchor.constraint(equalToConstant: 34).isActive = true; toolbar.addArrangedSubview(downloadButton)
        let device = actionButton("iphone", title: nil) { [weak self] in self?.interactOnDevice() }
        device.accessibilityLabel = "Interact on device"; device.widthAnchor.constraint(equalToConstant: 30).isActive = true; toolbar.addArrangedSubview(device)
        bookmarkRow.axis = .horizontal; bookmarkRow.spacing = 6; bookmarkScroll.showsHorizontalScrollIndicator = false
        bookmarkScroll.addSubview(bookmarkRow)
        configureFindBar()
        view.addSubview(toolbar); view.addSubview(bookmarkScroll); view.addSubview(webHost); view.addSubview(progress); view.addSubview(status); view.addSubview(findBar)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabel; status.lineBreakMode = .byTruncatingMiddle
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in self?.trimLiveTabs(limit: 1) })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.persistSession(); self?.trimLiveTabs(limit: 1) })
        observers.append(NotificationCenter.default.addObserver(forName: .workspaceChanged, object: nil, queue: .main) { [weak self] _ in self?.renderBookmarks() })
        observers.append(NotificationCenter.default.addObserver(forName: .downloadsChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            downloadButton.tintColor = DownloadStore.shared.runningCount > 0 ? DesktopStyle.accent : DesktopStyle.text
        })
        observers.append(NotificationCenter.default.addObserver(forName: .appearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.applyAppearance() })
        applyAppearance()
        renderBookmarks(); activateSelectedTab()
    }
    deinit {
        sessionSave?.cancel()
        findWork?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        for item in liveTabs.values { item.observation?.invalidate(); item.web.stopLoading(); item.web.navigationDelegate = nil; item.web.uiDelegate = nil }
    }
    private func configure(_ button: UIButton, symbol: String, label: String, action: @escaping () -> Void) {
        button.setImage(UIImage(systemName: symbol), for: .normal); button.tintColor = DesktopStyle.text; button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }
    private func styleButton(_ button: UIButton) {
        button.tintColor = DesktopStyle.text
        if var configuration = button.configuration { configuration.baseForegroundColor = DesktopStyle.text; button.configuration = configuration }
    }
    private func applyAppearance() {
        guard isViewLoaded else { return }
        view.backgroundColor = DesktopStyle.surface; progress.progressTintColor = DesktopStyle.accent
        findBar.backgroundColor = .secondarySystemBackground
        func style(_ view: UIView) {
            if let button = view as? UIButton { styleButton(button) }
            view.subviews.forEach(style)
        }
        style(view); renderTabs()
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { applyAppearance() }
    }
    private func configureFindBar() {
        findBar.axis = .horizontal; findBar.spacing = 4; findBar.alignment = .center; findBar.isHidden = true
        findBar.layer.cornerRadius = 8; findBar.isLayoutMarginsRelativeArrangement = true
        findBar.layoutMargins = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 4)
        findField.borderStyle = .roundedRect; findField.placeholder = "Find in page"; findField.delegate = self
        findField.font = .systemFont(ofSize: 13); findField.autocorrectionType = .no; findField.autocapitalizationType = .none; findField.returnKeyType = .search
        findField.addTarget(self, action: #selector(findTextChanged), for: .editingChanged)
        findBar.addArrangedSubview(findField)
        findStatus.font = .systemFont(ofSize: 10); findStatus.textColor = .secondaryLabel; findStatus.textAlignment = .right
        findStatus.text = "Type to find"; findStatus.widthAnchor.constraint(equalToConstant: 96).isActive = true; findBar.addArrangedSubview(findStatus)
        let controls: [(String, String, () -> Void)] = [
            ("chevron.up", "Previous match", { [weak self] in self?.findInPage(backwards: true) }),
            ("chevron.down", "Next match", { [weak self] in self?.findInPage(backwards: false) }),
            ("xmark", "Close find", { [weak self] in self?.closeFind() })]
        for item in controls {
            let button = actionButton(item.0, title: nil, action: item.2); button.accessibilityLabel = item.1
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true; findBar.addArrangedSubview(button)
        }
    }
    /// Used by the app menu bar and device keyboard shortcuts.
    func perform(_ command: BrowserCommand) {
        loadViewIfNeeded()
        if case .copyURL = command {
            UIPasteboard.general.url = web.url ?? URL(string: session.selected.url); status.text = "Address copied"; return
        }
        guard deviceSession == nil else { return }
        switch command {
        case .newTab: newTab()
        case .closeTab: if session.tabs.count == 1 { Workspace.shared.close(id) } else { closeTab(session.selectedID) }
        case .nextTab: session.selectNeighbor(backwards: false); activateSelectedTab()
        case .previousTab: session.selectNeighbor(backwards: true); activateSelectedTab()
        case .reload: web.reload()
        case .back: web.goBack()
        case .forward: web.goForward()
        case .find: showFind()
        case .zoomIn: changeZoom(by: 0.1)
        case .zoomOut: changeZoom(by: -0.1)
        case .actualSize: setZoom(1)
        case .pin:
            guard let url = web.url else { return }
            Workspace.shared.pin(title: web.title ?? url.host ?? "Website", url: url.absoluteString)
            status.text = "Pinned to Dock and bookmarks"
        case .downloads: showDownloads()
        case .copyURL: break
        }
    }
    @discardableResult func dismissTransientUI() -> Bool {
        if let panel = downloadsPanel { panel.removeFromSuperview(); downloadsPanel = nil; return true }
        if findVisible { closeFind(); return true }
        return false
    }
    private func changeZoom(by change: Double) { setZoom(((session.selected.pageZoom + change) * 100).rounded() / 100) }
    private func setZoom(_ value: Double) {
        session.setZoom(value, for: session.selectedID); web.pageZoom = CGFloat(session.selected.pageZoom)
        scheduleSessionSave(); status.text = "Page zoom: \(Int((session.selected.pageZoom * 100).rounded()))%"
    }
    private func showFind() {
        findVisible = true; findInputFocused = true; replaceFindInput = true; findBar.isHidden = false
        downloadsPanel?.removeFromSuperview(); downloadsPanel = nil
        view.setNeedsLayout(); findField.selectAll(nil)
        if view.window?.windowScene?.session.role == .windowApplication { findField.becomeFirstResponder() }
        if !(findField.text ?? "").isEmpty { scheduleFind() }
    }
    private func closeFind() {
        findVisible = false; findInputFocused = false; findBar.isHidden = true; findField.resignFirstResponder()
        findWork?.cancel(); findGeneration = UUID(); findCountCache = nil
        web.find("", configuration: WKFindConfiguration()) { _ in }
        view.setNeedsLayout()
    }
    @objc private func findTextChanged() { findInputFocused = true; replaceFindInput = false; scheduleFind() }
    private func scheduleFind() {
        if let text = findField.text, text.count > 256 { findField.text = String(text.prefix(256)) }
        findWork?.cancel(); findGeneration = UUID(); findCountCache = nil
        let work = DispatchWorkItem { [weak self] in self?.findInPage(backwards: false) }
        findWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    private func findInPage(backwards: Bool) {
        guard findVisible, deviceSession == nil else { return }
        findWork?.cancel(); findWork = nil
        let term = String((findField.text ?? "").prefix(256))
        guard !term.isEmpty else { findStatus.text = "Type to find"; web.find("", configuration: WKFindConfiguration()) { _ in }; return }
        let tab = session.selectedID, generation = UUID(); findGeneration = generation
        let configuration = WKFindConfiguration(); configuration.backwards = backwards; configuration.wraps = true; configuration.caseSensitive = false
        findStatus.text = "Searching…"
        let active = web
        active.find(term, configuration: configuration) { [weak self, weak active] result in
            guard let self, let active, findVisible, findGeneration == generation, session.selectedID == tab, findField.text == term else { return }
            guard result.matchFound else { findStatus.text = "No match"; return }
            findStatus.text = "Match found"
            if let count = findCountCache, count.tab == tab, count.term == term {
                showFindCount(count.count, capped: count.capped); return
            }
            // This count is deliberately labeled main-document text. Native WebKit
            // find can also match frames whose text an isolated script cannot read.
            let countScript = "const text=(document.body?.innerText??'').slice(0,2000000).toLocaleLowerCase(); const term=query.toLocaleLowerCase(); let count=0,offset=0; while(term && (offset=text.indexOf(term,offset))!==-1 && count<1000){count++;offset+=term.length;} return {count:count,capped:count>=1000||text.length>=2000000};"
            active.callAsyncJavaScript(countScript, arguments: ["query": term], in: nil, in: .defaultClient) { [weak self] response in
                guard let self, findGeneration == generation, session.selectedID == tab, findVisible else { return }
                if case .success(let value) = response, let values = value as? [String: Any], let count = values["count"] as? Int, count > 0 {
                    let capped = values["capped"] as? Bool ?? false
                    findCountCache = (tab, term, count, capped); showFindCount(count, capped: capped)
                }
            }
        }
    }
    private func showFindCount(_ count: Int, capped: Bool) { findStatus.text = "\(capped ? "≥" : "")\(count) in page text" }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tabScroll.frame = CGRect(x: 6, y: 3, width: max(0, view.bounds.width - 44), height: 34)
        addButton.frame = CGRect(x: view.bounds.width - 38, y: 3, width: 32, height: 32)
        tabRow.frame = CGRect(origin: .zero, size: tabRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)); tabScroll.contentSize = tabRow.bounds.size
        toolbar.frame = CGRect(x: 3, y: 39, width: view.bounds.width - 6, height: 42)
        let bookmarkHeight: CGFloat = Workspace.shared.bookmarks.isEmpty ? 0 : 26
        bookmarkScroll.frame = CGRect(x: 8, y: 81, width: view.bounds.width - 16, height: bookmarkHeight)
        bookmarkRow.frame = CGRect(origin: .zero, size: bookmarkRow.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)); bookmarkScroll.contentSize = bookmarkRow.bounds.size
        let findHeight: CGFloat = findVisible ? 42 : 0
        findBar.frame = CGRect(x: 8, y: 83 + bookmarkHeight, width: max(0, view.bounds.width - 16), height: findHeight)
        let top: CGFloat = 83 + bookmarkHeight + findHeight
        progress.frame = CGRect(x: 0, y: top - 2, width: view.bounds.width, height: 2)
        webHost.frame = CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, view.bounds.height - top - 20))
        if deviceSession == nil { liveTabs[session.selectedID]?.web.frame = webHost.bounds }
        status.frame = CGRect(x: 8, y: view.bounds.height - 20, width: view.bounds.width - 16, height: 20)
        downloadsPanel?.frame = CGRect(x: max(8, view.bounds.width - 388), y: 80, width: min(380, view.bounds.width - 16), height: max(100, min(360, view.bounds.height - 88)))
    }
    private func webView(for tabID: UUID, configuration: WKWebViewConfiguration? = nil, loadInitialURL: Bool = true) -> WKWebView {
        if let existing = liveTabs[tabID] { return existing.web }
        let config = configuration ?? WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true; config.defaultWebpagePreferences.preferredContentMode = .desktop
        let web = WKWebView(frame: .zero, configuration: config); web.navigationDelegate = self; web.uiDelegate = self
        web.pageZoom = CGFloat(session.tabs.first(where: { $0.id == tabID })?.pageZoom ?? 1)
        web.allowsBackForwardNavigationGestures = true; web.isOpaque = false; web.backgroundColor = .systemBackground
        liveTabs[tabID] = LiveTab(web: web)
        let observation = web.observe(\.estimatedProgress, options: [.new]) { [weak self, weak web] _, _ in
            guard let self, let web, self.liveTabs[self.session.selectedID]?.web === web else { return }
            self.updateNavigationUI()
        }
        liveTabs[tabID]?.observation = observation
        if loadInitialURL, let record = session.tabs.first(where: { $0.id == tabID }), let url = Address.resolve(record.url) { web.load(URLRequest(url: url)) }
        return web
    }
    private func tabID(for webView: WKWebView) -> UUID? { liveTabs.first(where: { $0.value.web === webView })?.key }
    func newTab(url: String = "https://www.apple.com") {
        guard deviceSession == nil else { return }
        guard session.add(url: url) != nil else { status.text = "Tab limit reached (\(BrowserSession.maximumTabs)). Close a tab to continue."; return }
        activateSelectedTab()
    }
    private func selectTab(_ id: UUID) {
        guard deviceSession == nil else { return }; session.select(id); activateSelectedTab()
    }
    private func closeTab(_ id: UUID) {
        guard deviceSession == nil else { return }
        if let item = liveTabs.removeValue(forKey: id) { item.observation?.invalidate(); item.web.stopLoading(); item.web.navigationDelegate = nil; item.web.uiDelegate = nil; item.web.removeFromSuperview() }
        session.close(id); activateSelectedTab()
    }
    private func activateSelectedTab() {
        findGeneration = UUID(); findCountCache = nil
        let active = web; liveTabs[session.selectedID]?.lastUsed = Date()
        webHost.subviews.forEach { if $0 !== active { $0.removeFromSuperview() } }
        if active.superview !== webHost { webHost.addSubview(active) }; active.frame = webHost.bounds
        renderTabs(); updateNavigationUI(); scheduleSessionSave(); trimLiveTabs(limit: 3)
        Workspace.shared.update(id) { $0.title = session.selected.title; $0.url = session.selected.url }
        if findVisible { scheduleFind() }
    }
    private func trimLiveTabs(limit: Int) {
        let candidates = liveTabs.filter { $0.key != session.selectedID }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (tabID, item) in candidates.prefix(max(0, liveTabs.count - limit)) {
            session.update(tabID, title: item.web.title, url: item.web.url?.absoluteString)
            item.observation?.invalidate(); item.web.stopLoading(); item.web.navigationDelegate = nil; item.web.uiDelegate = nil; item.web.removeFromSuperview(); liveTabs.removeValue(forKey: tabID)
        }
        scheduleSessionSave()
    }
    /// Keep the selected tab's DOM/history; release only extra background tabs.
    func setDesktopVisible(_ visible: Bool) {
        guard desktopVisible != visible else { return }; desktopVisible = visible
        if !visible { trimLiveTabs(limit: 1); persistSession() }
    }
    private func renderTabs() {
        tabRow.arrangedSubviews.forEach { tabRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        for record in session.tabs {
            let group = UIStackView(); group.axis = .horizontal; group.spacing = 0; group.alignment = .center
            group.backgroundColor = record.id == session.selectedID ? .tertiarySystemBackground : .secondarySystemBackground; group.layer.cornerRadius = 8
            group.layer.borderWidth = record.id == session.selectedID ? 1 : 0
            group.layer.borderColor = DesktopStyle.accent.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
            let select = actionButton("globe", title: String(record.title.prefix(22))) { [weak self] in self?.selectTab(record.id) }
            select.titleLabel?.font = .systemFont(ofSize: 11); select.widthAnchor.constraint(equalToConstant: 145).isActive = true; select.heightAnchor.constraint(equalToConstant: 30).isActive = true
            let close = actionButton("xmark", title: nil) { [weak self] in self?.closeTab(record.id) }; close.accessibilityLabel = "Close " + record.title
            styleButton(select); styleButton(close)
            close.widthAnchor.constraint(equalToConstant: 28).isActive = true; close.heightAnchor.constraint(equalToConstant: 30).isActive = true
            group.addArrangedSubview(select); group.addArrangedSubview(close); tabRow.addArrangedSubview(group)
        }
        view.setNeedsLayout(); view.layoutIfNeeded()
        if let index = session.tabs.firstIndex(where: { $0.id == session.selectedID }), index < tabRow.arrangedSubviews.count { tabScroll.scrollRectToVisible(tabRow.arrangedSubviews[index].frame, animated: false) }
    }
    private func renderBookmarks() {
        let bookmarks = Workspace.shared.bookmarks
        guard bookmarks.map(\.id) != bookmarksSignature else { return }
        bookmarksSignature = bookmarks.map(\.id)
        bookmarkRow.arrangedSubviews.forEach { bookmarkRow.removeArrangedSubview($0); $0.removeFromSuperview() }
        for bookmark in bookmarks {
            let button = actionButton("star.fill", title: String(bookmark.title.prefix(20))) { [weak self] in self?.navigate(bookmark.url) }
            styleButton(button)
            button.titleLabel?.font = .systemFont(ofSize: 11); bookmarkRow.addArrangedSubview(button)
        }; view.setNeedsLayout()
    }
    private func updateNavigationUI() {
        guard let active = liveTabs[session.selectedID]?.web else { return }
        if !address.isFirstResponder { address.text = active.url?.absoluteString ?? session.selected.url }
        back.isEnabled = active.canGoBack; forward.isEnabled = active.canGoForward
        reloadButton.setImage(UIImage(systemName: active.isLoading ? "xmark" : "arrow.clockwise"), for: .normal)
        progress.progress = Float(active.estimatedProgress); progress.isHidden = !active.isLoading || active.estimatedProgress >= 1
        status.text = active.url?.host ?? "Ready"
    }
    private func navigate(_ text: String) {
        guard deviceSession == nil, let url = Address.resolve(text) else { return }
        web.load(URLRequest(url: url)); downloadsPanel?.removeFromSuperview(); downloadsPanel = nil
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === findField { findInPage(backwards: false); return false }
        navigate(textField.text ?? ""); textField.resignFirstResponder(); return true
    }
    func textFieldDidBeginEditing(_ textField: UITextField) { findInputFocused = textField === findField }
    private func scheduleSessionSave() {
        sessionSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistSession() }
        sessionSave = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    private func persistSession() {
        sessionSave?.cancel(); sessionSave = nil
        if let data = try? JSONEncoder().encode(session) { UserDefaults.standard.set(data, forKey: "browser.session.\(id)") }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if tabID(for: webView) == session.selectedID { findGeneration = UUID(); findCountCache = nil; updateNavigationUI() }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { updateRecord(for: webView) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateRecord(for: webView); renderTabs()
        if tabID(for: webView) == session.selectedID, findVisible { scheduleFind() }
    }
    private func updateRecord(for webView: WKWebView) {
        guard let tabID = tabID(for: webView) else { return }
        session.update(tabID, title: webView.title, url: webView.url?.absoluteString); scheduleSessionSave()
        if tabID == session.selectedID {
            updateNavigationUI(); Workspace.shared.update(id) { $0.title = session.selected.title; $0.url = session.selected.url }
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled, tabID(for: webView) == session.selectedID else { return }; status.text = error.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if tabID(for: webView) == session.selectedID { status.text = "Page process ended. Reload to restore the page." }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let scheme = navigationAction.request.url?.scheme?.lowercased(), ["https", "http", "about", "blob", "data"].contains(scheme) else { decisionHandler(.cancel); return }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { DownloadStore.shared.accept(download); if downloadsPanel == nil { showDownloads() } }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { DownloadStore.shared.accept(download); if downloadsPanel == nil { showDownloads() } }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, deviceSession == nil, let url = navigationAction.request.url, ["https", "http", "about"].contains(url.scheme ?? ""), let tabID = session.add(url: url.absoluteString) else { return nil }
        // Return WebKit's requested configuration so opener/session semantics are retained.
        let popup = self.webView(for: tabID, configuration: configuration, loadInitialURL: false); activateSelectedTab(); return popup
    }
    func webViewDidClose(_ webView: WKWebView) { if let id = tabID(for: webView) { closeTab(id) } }
    func showDownloads() {
        if let panel = downloadsPanel { panel.removeFromSuperview(); downloadsPanel = nil; return }
        let panel = DownloadCenterView(frame: .zero); panel.onClose = { [weak self] in self?.downloadsPanel?.removeFromSuperview(); self?.downloadsPanel = nil }
        downloadsPanel = panel; view.addSubview(panel); view.setNeedsLayout()
    }
    private var presenter: UIViewController {
        var controller = Workspace.shared.localDesktop?.parent ?? self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
    private func editAddressOnDevice() {
        let alert = UIAlertController(title: "Address or search", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in field.text = self?.address.text; field.autocapitalizationType = .none; field.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self] _ in self?.navigate(alert.textFields?.first?.text ?? "") })
        presenter.present(alert, animated: true)
    }
    private func prompt(_ title: String, source: WKWebView, text: String? = nil, input: Bool = false, completion: @escaping (String?) -> Void) {
        guard tabID(for: source) == session.selectedID else { completion(nil); return }
        let alert = UIAlertController(title: title, message: source.url?.host, preferredStyle: .alert)
        if input { alert.addTextField { $0.text = text } }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(input ? alert.textFields?.first?.text ?? "" : "OK") })
        guard !(presenter is UIAlertController) else { completion(nil); return }; presenter.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { prompt(message, source: webView) { _ in completionHandler() } }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { prompt(message, source: webView) { completionHandler($0 != nil) } }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { self.prompt(prompt, source: webView, text: defaultText, input: true, completion: completionHandler) }
    func pointerClick(at point: CGPoint, secondary: Bool) {
        if let panel = downloadsPanel, panel.frame.contains(point) { panel.pointerClick(at: view.convert(point, to: panel), secondary: secondary); return }
        guard deviceSession == nil else { return }
        if findVisible, findBar.frame.contains(point) {
            if findField.frame.contains(view.convert(point, to: findBar)) { findInputFocused = true; replaceFindInput = false }
            return
        }
        let local = view.convert(point, to: web)
        guard web.bounds.contains(local) else {
            if address.frame.contains(view.convert(point, to: toolbar)) { editAddressOnDevice() }
            return
        }
        findInputFocused = false; findField.resignFirstResponder()
        script("""
        x = x * window.innerWidth / width;
        y = y * window.innerHeight / height;
        const e = document.elementFromPoint(x, y);
        if (!e) return;
        if (secondary) { e.dispatchEvent(new MouseEvent('contextmenu', {bubbles:true, clientX:x, clientY:y, button:2})); return; }
        e.focus();
        e.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,clientX:x,clientY:y,button:0}));
        e.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,clientX:x,clientY:y,button:0}));
        e.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:x,clientY:y,button:0}));
        """, arguments: ["x": Double(local.x), "y": Double(local.y), "width": Double(max(1, web.bounds.width)), "height": Double(max(1, web.bounds.height)), "secondary": secondary])
    }
    func pointerScroll(at point: CGPoint, delta: CGPoint) {
        if let panel = downloadsPanel, panel.frame.contains(point) { panel.pointerScroll(at: view.convert(point, to: panel), delta: delta); return }
        for scroll in [tabScroll, bookmarkScroll] where scroll.frame.contains(point) {
            let change = abs(delta.x) > abs(delta.y) ? delta.x : delta.y
            scroll.contentOffset.x = min(max(0, scroll.contentOffset.x + change), max(0, scroll.contentSize.width - scroll.bounds.width)); return
        }
        guard deviceSession == nil else { return }
        let local = view.convert(point, to: web)
        guard web.bounds.contains(local) else { return }
        script("""
        x = x * window.innerWidth / width;
        y = y * window.innerHeight / height;
        let e = document.elementFromPoint(x,y);
        while(e && e !== document.body) {
          const s = getComputedStyle(e);
          if (/(auto|scroll)/.test(s.overflowY) && e.scrollHeight > e.clientHeight) { e.scrollBy(dx,dy); return; }
          e = e.parentElement;
        }
        window.scrollBy(dx,dy);
        """, arguments: ["x": Double(local.x), "y": Double(local.y), "width": Double(max(1, web.bounds.width)), "height": Double(max(1, web.bounds.height)), "dx": Double(delta.x), "dy": Double(delta.y)])
    }
    func insertText(_ text: String) {
        guard deviceSession == nil else { return }
        if findVisible, findInputFocused {
            if text == "\u{1B}" { closeFind(); return }
            if text == "\n" { findInPage(backwards: false); return }
            if replaceFindInput { findField.text = ""; replaceFindInput = false }
            if text == "\u{8}" { findField.deleteBackward() }
            else { findField.insertText(String(text.prefix(256))) }
            scheduleFind(); return
        }
        script("""
        const e = document.activeElement;
        if (!e) return;
        if (text === '\\n') {
          if (e.tagName === 'TEXTAREA' || e.isContentEditable) { document.execCommand('insertText',false,'\\n'); }
          else if (e.form) { e.form.requestSubmit(); }
          return;
        }
        if (e instanceof HTMLInputElement || e instanceof HTMLTextAreaElement) {
          const start = e.selectionStart ?? e.value.length, end = e.selectionEnd ?? start;
          const deleting = text === '\\b';
          const left = deleting && start === end ? Math.max(0,start-1) : start;
          const value = e.value.slice(0,left) + (deleting ? '' : text) + e.value.slice(end);
          const proto = e instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(proto,'value').set.call(e,value);
          try { e.setSelectionRange(left + (deleting ? 0 : text.length),left + (deleting ? 0 : text.length)); } catch (_) {}
          e.dispatchEvent(new Event('input',{bubbles:true}));
          e.dispatchEvent(new Event('change',{bubbles:true}));
        } else if(e.isContentEditable) { document.execCommand(text === '\\b' ? 'delete' : 'insertText',false,text === '\\b' ? null : text); }
        """, arguments: ["text": text])
    }
    private func script(_ body: String, arguments: [String: Any]) {
        web.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { self?.status.text = "Web control: " + error.localizedDescription }
        }
    }
    func interactOnDevice() {
        guard deviceSession == nil, !(presenter is UIAlertController) else { return }
        let active = web
        let controller = WebInteractionController(web: active) { [weak self, weak active] in
            guard let self, let active else { return }
            deviceSession = nil; webHost.addSubview(active); view.setNeedsLayout()
        }
        deviceSession = controller
        let navigation = UINavigationController(rootViewController: controller); navigation.isModalInPresentation = true
        presenter.present(navigation, animated: true); status.text = "Interacting on device · return with Done"
    }
}

final class WebInteractionController: UIViewController {
    private let web: WKWebView
    private let finish: () -> Void
    init(web: WKWebView, finish: @escaping () -> Void) { self.web = web; self.finish = finish; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Interact on device"; view.backgroundColor = .systemBackground
        web.removeFromSuperview(); view.addSubview(web)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); web.frame = view.bounds.inset(by: view.safeAreaInsets) }
    @objc private func done() { web.removeFromSuperview(); finish(); dismiss(animated: true) }
}
