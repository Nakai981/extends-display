import UIKit

extension AppKind {
    var tint: UIColor {
        switch self {
        case .browser: return .systemIndigo
        case .files: return .systemBlue
        case .photos: return .systemPink
        case .notes: return .systemOrange
        case .calculator: return .systemGray
        case .settings: return .systemTeal
        }
    }
}

struct DesktopEntry {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: UIColor
    var image: UIImage? = nil
    var action: () -> Void
}

/// A desktop-hosted panel: native touches locally, explicit button/text/scroll routing externally.
final class DesktopPanel: UIView, UITextFieldDelegate {
    enum Mode: Equatable { case launcher, search, windows }
    let mode: Mode
    private let card = UIView()
    private let title = UILabel()
    private let search = UITextField()
    private let scroll = UIScrollView()
    private let list = UIStackView()
    private let footer = UILabel()
    private let close: UIButton
    private var entries: [DesktopEntry] = []
    private var buttons: [UIButton] = []
    private var selectedIndex = 0
    var onQuery: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var query: String { search.text ?? "" }
    init(mode: Mode) {
        self.mode = mode
        close = UIButton(type: .system)
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.4)
        card.backgroundColor = DesktopStyle.surface; card.layer.cornerRadius = 22
        card.layer.borderColor = DesktopStyle.border.cgColor; card.layer.borderWidth = 1
        card.layer.shadowOpacity = 0.35; card.layer.shadowRadius = 28; card.layer.shadowOffset = CGSize(width: 0, height: 14)
        addSubview(card)
        title.text = mode == .launcher ? "Applications" : mode == .windows ? "All windows" : "Search"
        title.font = .systemFont(ofSize: 22, weight: .semibold); title.textColor = .label; card.addSubview(title)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal); close.tintColor = .secondaryLabel
        close.accessibilityLabel = "Close panel"; close.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside); card.addSubview(close)
        search.borderStyle = .roundedRect; search.placeholder = mode == .search ? "Apps, files, websites…" : "Filter applications…"
        search.autocapitalizationType = .none; search.autocorrectionType = .no
        search.delegate = self; search.returnKeyType = .search
        search.addTarget(self, action: #selector(queryChanged), for: .editingChanged); card.addSubview(search)
        search.isHidden = mode == .windows
        list.axis = .vertical; list.spacing = 8; list.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list); card.addSubview(scroll)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        footer.text = "↑ ↓ Select · Enter Open · Esc Close · Type on your device"
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabel; card.addSubview(footer)
        accessibilityViewIsModal = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(mode == .windows ? 900 : 660, max(1, bounds.width - min(36, bounds.width * 0.08)))
        let height = min(620, max(1, bounds.height - min(64, bounds.height * 0.08)))
        card.frame = CGRect(x: (bounds.width - width) / 2, y: max(20, (bounds.height - height) / 2), width: width, height: height)
        title.frame = CGRect(x: 24, y: 18, width: width - 90, height: 30)
        close.frame = CGRect(x: width - 56, y: 14, width: 42, height: 42)
        search.frame = CGRect(x: 24, y: 64, width: width - 48, height: 40)
        let top: CGFloat = mode == .windows ? 64 : 118
        scroll.frame = CGRect(x: 20, y: top, width: width - 40, height: max(0, height - top - 44))
        footer.frame = CGRect(x: 24, y: height - 32, width: width - 48, height: 22)
    }
    func setEntries(_ entries: [DesktopEntry]) {
        let previous = self.entries.indices.contains(selectedIndex) ? self.entries[selectedIndex].title + "|" + self.entries[selectedIndex].subtitle : nil
        self.entries = Array(entries.prefix(60))
        selectedIndex = previous.flatMap { key in self.entries.firstIndex(where: { $0.title + "|" + $0.subtitle == key }) } ?? 0; buttons.removeAll()
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        if self.entries.isEmpty {
            let empty = UILabel(); empty.text = "No results"; empty.textColor = .secondaryLabel; empty.textAlignment = .center
            empty.heightAnchor.constraint(equalToConstant: 80).isActive = true; list.addArrangedSubview(empty); return
        }
        let columns = mode == .launcher ? 3 : mode == .windows ? 2 : 1
        for offset in stride(from: 0, to: self.entries.count, by: columns) {
            let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 8
            for entry in self.entries[offset..<min(offset + columns, self.entries.count)] {
                var configuration = UIButton.Configuration.filled()
                configuration.title = entry.title
                configuration.subtitle = entry.subtitle.isEmpty ? nil : entry.subtitle
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in var attributes = attributes; attributes.font = .systemFont(ofSize: 14, weight: .medium); return attributes }
                configuration.image = entry.image ?? UIImage(systemName: entry.symbol)
                configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: mode == .launcher ? 28 : 20)
                configuration.imagePlacement = columns > 1 ? .top : .leading; configuration.imagePadding = 10
                configuration.baseBackgroundColor = entry.tint.withAlphaComponent(0.12); configuration.baseForegroundColor = .label
                configuration.cornerStyle = .medium; configuration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
                let button = UIButton(configuration: configuration)
                button.contentHorizontalAlignment = columns == 1 ? .leading : .center
                button.addAction(UIAction { [weak self] _ in self?.onDismiss?(); entry.action() }, for: .touchUpInside)
                button.heightAnchor.constraint(equalToConstant: mode == .launcher ? 112 : mode == .windows ? 160 : 64).isActive = true
                row.addArrangedSubview(button)
                buttons.append(button)
            }
            while row.arrangedSubviews.count < columns { row.addArrangedSubview(UIView()) }
            list.addArrangedSubview(row)
        }
        scroll.contentOffset = .zero
        highlightSelection()
    }
    func insertText(_ text: String) {
        if text == "\u{1B}" { onDismiss?(); return }
        if text == "\n" { openSelected(); return }
        if mode == .windows { return }
        if text == "\u{8}" { if !(search.text ?? "").isEmpty { search.text?.removeLast() } }
        else { search.text = String(((search.text ?? "") + text).prefix(256)) }
        queryChanged()
    }
    func click(at point: CGPoint) {
        guard card.frame.contains(point) else { onDismiss?(); return }
        var hit = hitTest(point, with: nil)
        while let candidate = hit, candidate !== self {
            if let button = candidate as? UIButton { button.sendActions(for: .touchUpInside); return }
            hit = candidate.superview
        }
    }
    func scroll(by delta: CGPoint) {
        let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.contentOffset.y = min(maximum, max(0, scroll.contentOffset.y + delta.y))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self), !card.frame.contains(point) { onDismiss?() }
        super.touchesEnded(touches, with: event)
    }
    @objc private func queryChanged() { onQuery?(query) }
    func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }; selectedIndex = min(entries.count - 1, max(0, selectedIndex + delta)); highlightSelection()
    }
    func refreshAppearance() { card.backgroundColor = DesktopStyle.surface; card.layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor; highlightSelection() }
    private func highlightSelection() {
        for (index, button) in buttons.enumerated() { button.layer.borderWidth = index == selectedIndex ? 2 : 0; button.layer.borderColor = DesktopStyle.accent.cgColor }
        if selectedIndex < buttons.count { scroll.scrollRectToVisible(buttons[selectedIndex].convert(buttons[selectedIndex].bounds, to: scroll), animated: false) }
    }
    func openSelected() { guard entries.indices.contains(selectedIndex) else { return }; let entry = entries[selectedIndex]; onDismiss?(); entry.action() }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { openSelected(); return true }
}

/// Bounded sandbox-only name index. Filesystem I/O never runs in the render/input path.
final class DesktopFileIndex {
    static let shared = DesktopFileIndex()
    private var indexed: [URL] = []
    private var indexedAt = Date.distantPast
    private var indexing = false
    private var version = 0
    private var pending: (query: String, completion: ([URL]) -> Void)?
    private var observation: NSObjectProtocol?
    init() {
        observation = NotificationCenter.default.addObserver(forName: .filesChanged, object: nil, queue: .main) { [weak self] _ in self?.indexedAt = .distantPast; self?.version += 1 }
    }
    deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    func search(_ query: String, completion: @escaping ([URL]) -> Void) {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.count >= 2 else { pending = nil; completion([]); return }
        if Date().timeIntervalSince(indexedAt) < 20 { pending = nil; completion(Array(indexed.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(words) }.prefix(20))); return }
        pending = (words, completion)
        guard !indexing else { return }
        indexing = true; let requestVersion = version
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var urls: [URL] = []
            let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
            if let enumerator = FileManager.default.enumerator(at: Workspace.documents, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let url as URL in enumerator {
                    if urls.count >= 3000 { break }
                    if (try? url.resourceValues(forKeys: keys).isSymbolicLink) == true { enumerator.skipDescendants(); continue }
                    urls.append(url)
                }
            }
            DispatchQueue.main.async { [weak self = self] in
                guard let self else { return }
                self.indexing = false; self.indexed = urls; self.indexedAt = self.version == requestVersion ? Date() : .distantPast
                if let request = self.pending { self.pending = nil; request.completion(Array(urls.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(request.query) }.prefix(20))) }
            }
        }
    }
}
