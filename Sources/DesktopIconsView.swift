import UIKit

final class DesktopIconButton: UIButton {
    let url: URL
    init(item: FileBrowserItem) {
        url = item.url
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: item.symbol); config.title = item.name
        config.imagePlacement = .top; config.imagePadding = 7; config.baseForegroundColor = .white
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var attributes = $0; attributes.font = .systemFont(ofSize: 11, weight: .medium); return attributes }
        configuration = config; titleLabel?.numberOfLines = 2; titleLabel?.textAlignment = .center
        layer.cornerRadius = 8; layer.shadowColor = UIColor.black.cgColor; layer.shadowRadius = 2; layer.shadowOpacity = 0.5; layer.shadowOffset = CGSize(width: 0, height: 1)
        accessibilityLabel = item.name; accessibilityHint = "Double-click to open"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DesktopIconsView: UIView {
    private let loader = DirectoryLoader()
    private var icons: [DesktopIconButton] = []
    private var selected: URL?
    private var lastClick = Date.distantPast
    private var observation: NSObjectProtocol?
    private var pendingReload: DispatchWorkItem?
    var onOpen: ((URL) -> Void)?
    var onContext: ((URL, CGPoint) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        observation = NotificationCenter.default.addObserver(forName: .filesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pendingReload?.cancel(); let work = DispatchWorkItem { [weak self] in self?.refresh() }; self?.pendingReload = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { loader.cancel(); pendingReload?.cancel(); if let observation { NotificationCenter.default.removeObserver(observation) } }
    func refresh() {
        loader.load(Workspace.desktopFolder, sort: .name) { [weak self] result in
            guard let self, case .success(let items) = result else { return }
            let download = FileBrowserItem(url: Workspace.downloads, isDirectory: true, size: 0, modified: .distantPast)
            render([download] + Array(items.prefix(39)))
        }
    }
    private func render(_ items: [FileBrowserItem]) {
        if icons.map(\.url) == items.map(\.url) { return }
        icons.forEach { $0.removeFromSuperview() }; icons = []
        for item in items {
            let button = DesktopIconButton(item: item)
            button.addAction(UIAction { [weak self, weak button] _ in if let button { self?.choose(button) } }, for: .touchUpInside)
            let double = UITapGestureRecognizer(target: self, action: #selector(openDouble(_:))); double.numberOfTapsRequired = 2; double.cancelsTouchesInView = false; button.addGestureRecognizer(double)
            let secondary = UITapGestureRecognizer(target: self, action: #selector(context(_:))); secondary.buttonMaskRequired = .secondary; button.addGestureRecognizer(secondary)
            addSubview(button); icons.append(button)
        }
        setNeedsLayout(); updateSelection()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let rows = max(1, Int(max(1, bounds.height - 20) / 104))
        for (index, icon) in icons.enumerated() {
            let column = index / rows, row = index % rows
            icon.frame = CGRect(x: max(4, bounds.width - 104 - CGFloat(column) * 100), y: 12 + CGFloat(row) * 104, width: 92, height: 96)
            icon.isHidden = CGFloat(column + 1) * 100 > bounds.width
        }
    }
    func item(at point: CGPoint) -> URL? { icons.first { !$0.isHidden && $0.frame.contains(point) }?.url }
    func click(at point: CGPoint) {
        guard let icon = icons.first(where: { !$0.isHidden && $0.frame.contains(point) }) else { selected = nil; updateSelection(); return }
        if selected == icon.url, Date().timeIntervalSince(lastClick) < 0.45 { onOpen?(icon.url); lastClick = .distantPast }
        else { choose(icon); lastClick = Date() }
    }
    private func choose(_ icon: DesktopIconButton) { selected = icon.url; updateSelection() }
    private func updateSelection() { for icon in icons { icon.backgroundColor = selected == icon.url ? UIColor.systemBlue.withAlphaComponent(0.28) : .clear; icon.layer.borderWidth = selected == icon.url ? 1 : 0; icon.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor } }
    @objc private func openDouble(_ gesture: UITapGestureRecognizer) { if let icon = gesture.view as? DesktopIconButton { onOpen?(icon.url) } }
    @objc private func context(_ gesture: UITapGestureRecognizer) { if let icon = gesture.view as? DesktopIconButton { selected = icon.url; updateSelection(); onContext?(icon.url, gesture.location(in: self)) } }
}
