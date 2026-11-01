import UIKit
import WebKit
import UniformTypeIdentifiers

final class SystemSettingsController: ToolController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private enum Category: Int, CaseIterable {
        case appearance, desktop, input, browser, about
        var title: String { ["Appearance", "Desktop & Dock", "Input", "Browser & Storage", "About"][rawValue] }
        var symbol: String { ["paintpalette.fill", "menubar.dock.rectangle", "keyboard", "globe", "info.circle.fill"][rawValue] }
    }
    private struct Row {
        var title: String
        var detail: String? = nil
        var symbol: String? = nil
        var checked: Bool = false
        var toggle: Bool? = nil
        var destructive = false
        var action: (() -> Void)? = nil
    }
    private struct Section { var title: String; var rows: [Row]; var footer: String? = nil }
    private let sidebar = UITableView(frame: .zero, style: .plain)
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let titleLabel = UILabel()
    private let categoryButton = UIButton(type: .system)
    private var category = Category.appearance
    private var sections: [Section] = []
    private var observers: [NSObjectProtocol] = []
    private let preferences = DesktopPreferences.shared

    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemGroupedBackground
        sidebar.backgroundColor = .secondarySystemGroupedBackground; sidebar.separatorStyle = .none; sidebar.rowHeight = 44
        [sidebar, table].forEach { $0.dataSource = self; $0.delegate = self; view.addSubview($0) }
        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold); titleLabel.textColor = .label; view.addSubview(titleLabel)
        categoryButton.setImage(UIImage(systemName: "sidebar.left"), for: .normal); categoryButton.addAction(UIAction { [weak self] _ in self?.chooseCategory() }, for: .touchUpInside); view.addSubview(categoryButton)
        for name in [Notification.Name.appearanceChanged, .workspaceChanged, .downloadsChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reload() })
        }
        reload()
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let sidebarWidth: CGFloat = view.bounds.width >= 640 ? 190 : 0
        sidebar.isHidden = sidebarWidth == 0
        sidebar.frame = CGRect(x: 0, y: 0, width: sidebarWidth, height: view.bounds.height)
        categoryButton.isHidden = sidebarWidth != 0; categoryButton.frame = CGRect(x: 8, y: 12, width: 38, height: 38)
        titleLabel.frame = CGRect(x: sidebarWidth + (sidebarWidth == 0 ? 52 : 24), y: 15, width: max(0, view.bounds.width - sidebarWidth - 76), height: 36)
        table.frame = CGRect(x: sidebarWidth, y: 64, width: view.bounds.width - sidebarWidth, height: max(0, view.bounds.height - 64))
    }
    private func reload() {
        guard isViewLoaded else { return }
        overrideUserInterfaceStyle = preferences.interfaceStyle; view.tintColor = preferences.accent.color
        titleLabel.text = category.title; sections = makeSections(); table.reloadData(); sidebar.reloadData()
    }
    private func makeSections() -> [Section] {
        switch category {
        case .appearance:
            let styles = DesktopAppearance.allCases.map { style in Row(title: style.title, symbol: style == .system ? "circle.lefthalf.filled" : style == .dark ? "moon.fill" : "sun.max.fill", checked: preferences.appearance == style, action: { [weak self] in self?.preferences.appearance = style }) }
            let accents = DesktopAccent.allCases.map { accent in Row(title: accent.title, symbol: "circle.fill", checked: preferences.accent == accent, action: { [weak self] in self?.preferences.accent = accent }) }
            return [Section(title: "Appearance", rows: styles, footer: "System follows the appearance selected on your iPhone or iPad."), Section(title: "Accent color", rows: accents), Section(title: "Accessibility", rows: [Row(title: "Reduce Motion", detail: "Use fewer desktop animations", toggle: preferences.reduceMotion, action: { [weak self] in guard let self else { return }; preferences.reduceMotion.toggle() })])]
        case .desktop:
            var wallpapers = DesktopPreferences.wallpaperTitles.enumerated().map { index, name in Row(title: name, symbol: "mountain.2.fill", checked: !preferences.hasCustomWallpaper && preferences.wallpaperPreset == index, action: { [weak self] in guard let self else { return }; preferences.clearCustomWallpaper(); preferences.wallpaperPreset = index }) }
            wallpapers.append(Row(title: "Choose Image…", detail: preferences.hasCustomWallpaper ? "Custom image selected" : "Import an image from Files", symbol: "photo", action: { [weak self] in self?.chooseWallpaper() }))
            if preferences.hasCustomWallpaper { wallpapers.append(Row(title: "Remove Custom Image", symbol: "xmark.circle", action: { [weak self] in self?.preferences.clearCustomWallpaper() })) }
            return [Section(title: "Wallpaper", rows: wallpapers, footer: "Built-in landscapes are original vector artwork. Imported images are resized for efficient display."), Section(title: "Dock", rows: [Row(title: "Automatically Hide Dock", detail: "Reveal it near the bottom edge", toggle: preferences.dockAutoHide, action: { [weak self] in guard let self else { return }; preferences.dockAutoHide.toggle() }), Row(title: "Icon Size", detail: "\(Int(preferences.dockSize)) pt", symbol: "square.resize", action: { [weak self] in self?.chooseDockSize() })])]
        case .input:
            return [Section(title: "Trackpad", rows: [Row(title: "Pointer Speed", detail: String(format: "%.1f×", Workspace.shared.pointerSpeed), symbol: "cursorarrow.motionlines", action: { [weak self] in self?.choosePointerSpeed() })], footer: "One finger moves, two fingers scroll, and holding before moving drags a window."), Section(title: "Keyboard shortcuts", rows: [Row(title: "New Browser", detail: "⌘ N"), Row(title: "Search", detail: "⌃ Space"), Row(title: "All Windows", detail: "⌘ ↑"), Row(title: "Next Window", detail: "⌃ Tab"), Row(title: "Close Window", detail: "⌘ W"), Row(title: "Close Panel", detail: "Esc")], footer: "Use the input field on your device for text entry. Some websites require Web on device for direct interaction.")]
        case .browser:
            return [Section(title: "Browser", rows: [Row(title: "Open Browser", symbol: "globe", action: { Workspace.shared.activate(.browser) }), Row(title: "Pinned Websites", detail: "\(Workspace.shared.bookmarks.count) websites", symbol: "pin.fill", action: { [weak self] in self?.managePinnedSites() }), Row(title: "Clear Website Data…", detail: "Cookies, cache and website storage", symbol: "trash", destructive: true, action: { [weak self] in self?.confirmClearWebsiteData() })], footer: "Clearing website data signs you out of websites and affects all browser windows."), Section(title: "Files & downloads", rows: [Row(title: "Open Downloads", detail: "\(DownloadStore.shared.runningCount) downloading", symbol: "arrow.down.circle", action: { DownloadStore.shared.openDownloads() }), Row(title: "Open App Files", symbol: "folder", action: { Workspace.shared.activate(.files) })], footer: "Files outside this app are available only after you select them in the system file picker.")]
        case .about:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3"
            return [Section(title: "ExtendDesk", rows: [Row(title: "Version", detail: version, symbol: "display"), Row(title: "Desktop for iPhone & iPad", detail: "External display workspace")], footer: "Connect a compatible display, then use your device or a mouse and keyboard to control your desktop."), Section(title: "Preferences", rows: [Row(title: "Reset Appearance…", detail: "Restore wallpaper, colors and Dock settings", symbol: "arrow.counterclockwise", action: { [weak self] in self?.confirmResetAppearance() })])]
        }
    }
    private func chooseCategory() {
        choose("Settings", options: Category.allCases.map(\.title)) { [weak self] index in self?.category = Category(rawValue: index) ?? .appearance; self?.reload() }
    }
    private func chooseDockSize() {
        let sizes: [CGFloat] = [36, 44, 56]
        choose("Dock Icon Size", options: ["Small · 36 pt", "Standard · 44 pt", "Large · 56 pt"]) { [weak self] in self?.preferences.dockSize = sizes[$0] }
    }
    private func choosePointerSpeed() {
        choose("Pointer Speed", options: ["Slow · 0.8×", "Normal · 1.5×", "Fast · 2.5×"]) { [weak self] in Workspace.shared.pointerSpeed = [0.8, 1.5, 2.5][$0]; self?.reload() }
    }
    private func choose(_ title: String, options: [String], completion: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (index, value) in options.enumerated() { alert.addAction(UIAlertAction(title: value, style: .default) { _ in completion(index) }) }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = presenter.view; alert.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 80, width: 1, height: 1)
        presenter.present(alert, animated: true)
    }
    private func chooseWallpaper() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: false); picker.delegate = self
        presenter.present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        preferences.importWallpaper(from: url) { [weak self] result in if case .failure(let error) = result { self?.alert("Wallpaper could not be imported", message: error.localizedDescription) } }
    }
    private func managePinnedSites() {
        guard !Workspace.shared.bookmarks.isEmpty else { alert("No pinned websites", message: "Use the star button in the browser to pin a website."); return }
        let items = Workspace.shared.bookmarks
        choose("Remove a pinned website", options: items.map(\.title)) { Workspace.shared.unpin(items[$0].id) }
    }
    private func confirmClearWebsiteData() {
        let confirmation = UIAlertController(title: "Clear website data?", message: "This removes cookies, cache and website storage for all browser windows. You may need to sign in again.", preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmation.addAction(UIAlertAction(title: "Clear Data", style: .destructive) { [weak self] _ in
            WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { DispatchQueue.main.async { self?.alert("Website data cleared") } }
        }); presenter.present(confirmation, animated: true)
    }
    private func confirmResetAppearance() {
        let confirmation = UIAlertController(title: "Reset appearance?", message: "Restore the default wallpaper, accent, appearance and Dock preferences.", preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmation.addAction(UIAlertAction(title: "Reset", style: .default) { [weak self] _ in self?.preferences.resetAppearance() }); presenter.present(confirmation, animated: true)
    }
    func numberOfSections(in tableView: UITableView) -> Int { tableView === sidebar ? 1 : sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tableView === sidebar ? Category.allCases.count : sections[section].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { tableView === sidebar ? "Settings" : sections[section].title }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? { tableView === sidebar ? nil : sections[section].footer }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.font = .systemFont(ofSize: 13, weight: .medium); cell.detailTextLabel?.font = .systemFont(ofSize: 12); cell.detailTextLabel?.numberOfLines = 2
        if tableView === sidebar {
            let item = Category.allCases[indexPath.row]
            cell.textLabel?.text = item.title; cell.imageView?.image = UIImage(systemName: item.symbol); cell.imageView?.tintColor = preferences.accent.color
            cell.backgroundColor = category == item ? preferences.accent.color.withAlphaComponent(0.15) : .clear
            cell.accessibilityTraits = category == item ? [.button, .selected] : .button
        } else {
            let row = sections[indexPath.section].rows[indexPath.row]
            cell.textLabel?.text = row.title; cell.detailTextLabel?.text = row.detail
            if let symbol = row.symbol { cell.imageView?.image = UIImage(systemName: symbol); cell.imageView?.tintColor = category == .appearance && indexPath.section == 1 ? DesktopAccent.allCases[indexPath.row].color : preferences.accent.color }
            if let toggle = row.toggle {
                let control = UISwitch(); control.isOn = toggle; control.onTintColor = preferences.accent.color
                control.addAction(UIAction { _ in row.action?() }, for: .valueChanged); cell.accessoryView = control
            } else { cell.accessoryType = row.checked ? .checkmark : row.action == nil ? .none : .disclosureIndicator }
            if row.destructive { cell.textLabel?.textColor = .systemRed }
            cell.selectionStyle = row.action == nil ? .none : .default
        }
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView === sidebar { category = Category.allCases[indexPath.row]; reload() }
        else { sections[indexPath.section].rows[indexPath.row].action?() }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    override func pointerClick(at point: CGPoint, secondary: Bool) {
        for candidate in [sidebar, table] where !candidate.isHidden && candidate.frame.contains(point) {
            if let index = candidate.indexPathForRow(at: view.convert(point, to: candidate)) { tableView(candidate, didSelectRowAt: index) }; return
        }
        super.pointerClick(at: point, secondary: secondary)
    }
}
