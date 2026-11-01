import UIKit

struct DesktopMenuItem {
    var title: String
    var symbol: String = ""
    var shortcut: String = ""
    var enabled = true
    var checked = false
    var destructive = false
    var action: () -> Void
}

final class DesktopMenuView: UIView {
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let stack = UIStackView()
    private let scroll = UIScrollView()
    private let items: [DesktopMenuItem]
    private let origin: CGPoint
    private var buttons: [UIButton] = []
    private var selection = 0
    var onDismiss: (() -> Void)?
    init(items: [DesktopMenuItem], origin: CGPoint) {
        self.items = items; self.origin = origin
        super.init(frame: .zero)
        material.clipsToBounds = true; material.layer.cornerRadius = 12; material.layer.borderWidth = 1; material.layer.borderColor = DesktopStyle.border.cgColor
        addSubview(material); material.contentView.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 2; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        for (index, item) in items.enumerated() {
            var config = UIButton.Configuration.plain(); config.title = item.title
            let symbol = item.checked ? "checkmark" : item.symbol
            config.image = symbol.isEmpty ? nil : UIImage(systemName: symbol)
            config.imagePadding = 8; config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: item.shortcut.isEmpty ? 10 : 72)
            config.baseForegroundColor = item.destructive ? .systemRed : .label
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var attributes = $0; attributes.font = .systemFont(ofSize: 13); return attributes }
            let button = UIButton(configuration: config); button.contentHorizontalAlignment = .leading; button.isEnabled = item.enabled
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true; button.layer.cornerRadius = 6
            if !item.shortcut.isEmpty { let key = UILabel(); key.text = item.shortcut; key.textColor = .secondaryLabel; key.font = .systemFont(ofSize: 11); key.textAlignment = .right; key.translatesAutoresizingMaskIntoConstraints = false; key.isUserInteractionEnabled = false; button.addSubview(key); NSLayoutConstraint.activate([key.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10), key.centerYAnchor.constraint(equalTo: button.centerYAnchor)]) }
            button.addAction(UIAction { [weak self] _ in self?.activate(index) }, for: .touchUpInside)
            stack.addArrangedSubview(button); buttons.append(button)
        }
        selection = items.firstIndex(where: \.enabled) ?? 0; updateHighlight()
        accessibilityViewIsModal = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = min(296, max(1, bounds.width - 16))
        let height = min(CGFloat(items.count) * 36 + 12, max(1, bounds.height - 20))
        material.frame = CGRect(x: min(max(8, origin.x), max(8, bounds.width - width - 8)), y: min(max(8, origin.y), max(8, bounds.height - height - 8)), width: width, height: height)
        scroll.frame = material.bounds.insetBy(dx: 6, dy: 6)
    }
    func click(at point: CGPoint) {
        guard material.frame.contains(point) else { onDismiss?(); return }
        if let index = buttons.firstIndex(where: { $0.bounds.contains(convert(point, to: $0)) }) { activate(index) }
    }
    func hover(at point: CGPoint) {
        if let index = buttons.firstIndex(where: { $0.bounds.contains(convert(point, to: $0)) && $0.isEnabled }), index != selection { selection = index; updateHighlight() }
    }
    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        var next = selection
        for _ in items.indices { next = (next + (delta < 0 ? -1 : 1) + items.count) % items.count; if items[next].enabled { selection = next; updateHighlight(); return } }
    }
    func openSelected() { activate(selection) }
    func refreshAppearance() { material.layer.borderColor = DesktopStyle.border.resolvedColor(with: traitCollection).cgColor; updateHighlight() }
    func scroll(by delta: CGPoint) { scroll.contentOffset.y = min(max(0, scroll.contentOffset.y + delta.y), max(0, scroll.contentSize.height - scroll.bounds.height)) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let point = touches.first?.location(in: self), !material.frame.contains(point) { onDismiss?() }; super.touchesEnded(touches, with: event) }
    private func activate(_ index: Int) { guard items.indices.contains(index), items[index].enabled else { return }; onDismiss?(); items[index].action() }
    private func updateHighlight() { for (index, button) in buttons.enumerated() { button.backgroundColor = index == selection && button.isEnabled ? DesktopStyle.accent.withAlphaComponent(0.18) : .clear } }
}

enum WindowPlacement: CaseIterable, Equatable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, center, fill, restore
    var title: String {
        switch self {
        case .left: return "Tile Left Half"
        case .right: return "Tile Right Half"
        case .topLeft: return "Tile Top Left"
        case .topRight: return "Tile Top Right"
        case .bottomLeft: return "Tile Bottom Left"
        case .bottomRight: return "Tile Bottom Right"
        case .center: return "Center Window"
        case .fill: return "Fill Desktop"
        case .restore: return "Restore Size"
        }
    }
    func frame(in bounds: CGRect, current: CGRect) -> CGRect {
        let inset = bounds.insetBy(dx: min(6, bounds.width / 8), dy: min(6, bounds.height / 8))
        let halfWidth = max(1, (inset.width - 6) / 2), halfHeight = max(1, (inset.height - 6) / 2)
        switch self {
        case .left: return CGRect(x: inset.minX, y: inset.minY, width: halfWidth, height: inset.height)
        case .right: return CGRect(x: inset.maxX - halfWidth, y: inset.minY, width: halfWidth, height: inset.height)
        case .topLeft: return CGRect(x: inset.minX, y: inset.minY, width: halfWidth, height: halfHeight)
        case .topRight: return CGRect(x: inset.maxX - halfWidth, y: inset.minY, width: halfWidth, height: halfHeight)
        case .bottomLeft: return CGRect(x: inset.minX, y: inset.maxY - halfHeight, width: halfWidth, height: halfHeight)
        case .bottomRight: return CGRect(x: inset.maxX - halfWidth, y: inset.maxY - halfHeight, width: halfWidth, height: halfHeight)
        case .center: return CGRect(x: bounds.midX - current.width / 2, y: bounds.midY - current.height / 2, width: current.width, height: current.height)
        case .fill: return inset
        case .restore: return current
        }
    }
}
