import UIKit
import PDFKit
import AVKit
import QuickLook
import UniformTypeIdentifiers
import ImageIO
import Darwin

class ToolController: UIViewController, DesktopContent {
    var presenter: UIViewController {
        var controller = Workspace.shared.localDesktop?.parent ?? self
        while let presented = controller.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
    func pointerClick(at point: CGPoint, secondary: Bool) {
        var hit = view.hitTest(point, with: nil)
        while let candidate = hit {
            if let control = candidate as? UIControl { control.sendActions(for: .touchUpInside); return }
            if let table = candidate as? UITableView {
                if let index = table.indexPathForRow(at: view.convert(point, to: table)) { table.delegate?.tableView?(table, didSelectRowAt: index) }; return
            }
            hit = candidate.superview
        }
    }
    func pointerScroll(at point: CGPoint, delta: CGPoint) {
        var hit = view.hitTest(point, with: nil)
        while let candidate = hit {
            if let scroll = candidate as? UIScrollView {
                let x = min(max(-scroll.adjustedContentInset.left, scroll.contentOffset.x + delta.x), max(0, scroll.contentSize.width - scroll.bounds.width))
                let y = min(max(-scroll.adjustedContentInset.top, scroll.contentOffset.y + delta.y), max(0, scroll.contentSize.height - scroll.bounds.height))
                scroll.setContentOffset(CGPoint(x: x, y: y), animated: false); return
            }; hit = candidate.superview
        }
    }
    func insertText(_ text: String) {}
    func alert(_ title: String, message: String? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default)); presenter.present(alert, animated: true)
    }
    func ask(_ title: String, initial: String = "", completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = initial }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { completion(text) }
        }); presenter.present(alert, animated: true)
    }
}

final class FilesController: ToolController, UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    private let toolbar = UIStackView()
    private let toolbarScroll = UIScrollView()
    private let sidebar = UITableView(frame: .zero, style: .plain)
    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let path = UILabel()
    private let footer = UILabel()
    private let preview = UIView()
    private let empty = UILabel()
    private let loader = DirectoryLoader()
    private let trash = FileTrashStore(root: Workspace.documents)
    private var current = Workspace.documents
    private var files: [FileBrowserItem] = []
    private var granted: [URL] = []
    private var previewURL: URL?
    private var previewChild: UIViewController?
    private var player: AVPlayer?
    private var observers: [NSObjectProtocol] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingRefresh: DispatchWorkItem?
    private var previewGeneration = UUID()
    private var clipboard: (url: URL, move: Bool)?
    private var gridMode = UserDefaults.standard.bool(forKey: "files.grid")
    private var sort = FileSortOrder(rawValue: UserDefaults.standard.integer(forKey: "files.sort")) ?? .name
    private var initialURL: URL?
    private var lastCollectionSize = CGSize.zero
    private static let work = FileOperations.queue
    private static let previews = DispatchQueue(label: "extenddesk.files.previews", qos: .userInitiated)
    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        toolbar.axis = .horizontal; toolbar.spacing = 2
        toolbar.addArrangedSubview(actionButton("sidebar.left", title: "Places") { [weak self] in self?.showPlaces() })
        toolbar.addArrangedSubview(actionButton("arrow.up", title: nil) { [weak self] in self?.up() })
        toolbar.addArrangedSubview(actionButton("arrow.clockwise", title: nil) { [weak self] in self?.reload() })
        toolbar.addArrangedSubview(actionButton("folder.badge.plus", title: nil) { [weak self] in self?.newFolder() })
        toolbar.addArrangedSubview(actionButton("square.and.arrow.down", title: "Import") { [weak self] in self?.pick(folder: false) })
        toolbar.addArrangedSubview(actionButton("externaldrive", title: "Mount") { [weak self] in self?.pick(folder: true) })
        toolbar.addArrangedSubview(actionButton("doc.on.clipboard", title: nil) { [weak self] in self?.paste() })
        toolbar.addArrangedSubview(actionButton("square.grid.2x2", title: nil) { [weak self] in self?.toggleLayout() })
        toolbar.addArrangedSubview(actionButton("arrow.up.arrow.down", title: nil) { [weak self] in self?.changeSort() })
        toolbarScroll.showsHorizontalScrollIndicator = false; toolbarScroll.addSubview(toolbar); view.addSubview(toolbarScroll)
        view.addSubview(path); view.addSubview(sidebar); view.addSubview(collection); view.addSubview(preview); view.addSubview(footer)
        path.font = .systemFont(ofSize: 12, weight: .medium); path.textColor = .secondaryLabel; path.lineBreakMode = .byTruncatingMiddle
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabel
        sidebar.backgroundColor = .secondarySystemBackground; sidebar.dataSource = self; sidebar.delegate = self
        sidebar.rowHeight = 38; sidebar.separatorStyle = .none
        collection.backgroundColor = .systemBackground; collection.dataSource = self; collection.delegate = self
        collection.register(FileItemCell.self, forCellWithReuseIdentifier: "file")
        empty.text = "Loading…"; empty.numberOfLines = 0; empty.textAlignment = .center; empty.textColor = .secondaryLabel
        collection.backgroundView = empty
        for name in [Notification.Name("filesChanged"), UIApplication.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleReload() })
        }
        if let initialURL {
            let isDirectory = (try? initialURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            current = isDirectory ? initialURL : initialURL.deletingLastPathComponent()
            if !isDirectory { DispatchQueue.main.async { [weak self] in self?.open(initialURL) } }
        }
        watchDirectory(); reload()
    }
    deinit {
        loader.cancel(); watcher?.cancel(); pendingRefresh?.cancel(); player?.pause()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        granted.forEach { $0.stopAccessingSecurityScopedResource() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width, height = view.bounds.height
        toolbarScroll.frame = CGRect(x: 0, y: 0, width: width, height: 44)
        let toolbarSize = toolbar.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        toolbar.frame = CGRect(x: 6, y: 0, width: max(width - 12, toolbarSize.width), height: 44)
        toolbarScroll.contentSize = CGSize(width: toolbar.frame.maxX + 6, height: 44)
        path.frame = CGRect(x: 12, y: 44, width: width - 24, height: 28)
        let sideWidth: CGFloat = width >= 640 ? 160 : 0
        sidebar.isHidden = sideWidth == 0; sidebar.frame = CGRect(x: 0, y: 72, width: sideWidth, height: max(0, height - 96))
        let available = max(0, width - sideWidth)
        let previewWidth: CGFloat = previewURL == nil || width < 620 ? 0 : max(220, available * 0.52)
        collection.frame = CGRect(x: sideWidth, y: 72, width: max(0, available - previewWidth), height: max(0, height - 96))
        preview.isHidden = previewWidth == 0; preview.frame = CGRect(x: collection.frame.maxX, y: 72, width: previewWidth, height: max(0, height - 96))
        preview.subviews.forEach { $0.frame = preview.bounds }
        footer.frame = CGRect(x: 12, y: height - 24, width: max(0, width - 24), height: 24)
        if lastCollectionSize != collection.bounds.size { lastCollectionSize = collection.bounds.size; collection.collectionViewLayout.invalidateLayout() }
    }
    private var places: [(title: String, symbol: String, url: URL?)] {
        [("App Files", "folder", Workspace.documents), ("Downloads", "arrow.down.circle", Workspace.downloads), ("Notes", "note.text", Workspace.documents.appendingPathComponent("Notes", isDirectory: true)), ("Trash", "trash", nil)] + granted.map { ($0.lastPathComponent, "externaldrive", Optional($0)) }
    }
    private func navigate(_ url: URL) {
        current = url; clearPreview(); loader.cancel(); files = []; collection.reloadData(); watchDirectory(); reload(); sidebar.reloadData()
    }
    private func watchDirectory() {
        watcher?.cancel(); watcher = nil
        let descriptor = Darwin.open(current.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib, .revoke], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(descriptor) }; watcher = source; source.resume()
    }
    private func scheduleReload() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reload() }; pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
    }
    private func reload() {
        path.text = current.path.replacingOccurrences(of: Workspace.documents.path, with: "App Files")
        if files.isEmpty { empty.text = "Loading…" }; footer.text = "Loading folder…"
        loader.load(current, sort: sort) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                if self.files != items { self.files = items; self.collection.reloadData() }
                self.empty.text = items.isEmpty ? "This folder is empty" : ""
                self.footer.text = "\(items.count) items · Sorted by \(self.sort.title.lowercased())"
            case .failure(let error): self.files = []; self.collection.reloadData(); self.empty.text = error.localizedDescription; self.footer.text = "Could not read folder · Refresh to retry"
            }
        }
    }
    private func up() {
        guard !([Workspace.documents] + granted).contains(current.standardizedFileURL) else { return }
        let parent = current.deletingLastPathComponent()
        guard ([Workspace.documents] + granted).contains(where: { FileOperations.contains(parent, in: $0) }) else { return }
        navigate(parent)
    }
    private func showPlaces() {
        let alert = UIAlertController(title: "Places", message: nil, preferredStyle: .actionSheet)
        for place in places { alert.addAction(UIAlertAction(title: place.title, style: .default) { [weak self] _ in if let url = place.url { self?.navigate(url) } else { self?.showTrash() } }) }
        showMenu(alert)
    }
    private func toggleLayout() { gridMode.toggle(); UserDefaults.standard.set(gridMode, forKey: "files.grid"); collection.reloadData(); collection.collectionViewLayout.invalidateLayout() }
    private func changeSort() {
        let alert = UIAlertController(title: "Sort files", message: nil, preferredStyle: .actionSheet)
        for option in FileSortOrder.allCases { alert.addAction(UIAlertAction(title: option.title, style: .default) { [weak self] _ in self?.sort = option; UserDefaults.standard.set(option.rawValue, forKey: "files.sort"); self?.reload() }) }; showMenu(alert)
    }
    private func newFolder() {
        ask("New folder") { [weak self] name in
            guard let self else { return }
            guard FileOperations.validName(name) else { self.alert("Invalid name"); return }
            let destination = self.current.appendingPathComponent(name, isDirectory: true)
            self.perform("Create folder") { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
        }
    }
    private func perform(_ title: String, action: @escaping () throws -> Void, completion: (() -> Void)? = nil) {
        footer.text = title + "…"; let scopes = granted
        Self.work.async { [weak self] in
            let leases = scopes.filter { $0.startAccessingSecurityScopedResource() }
            defer { leases.forEach { $0.stopAccessingSecurityScopedResource() } }
            do {
                try action()
                DispatchQueue.main.async { [weak self = self] in completion?(); NotificationCenter.default.post(name: Notification.Name("filesChanged"), object: nil); self?.reload() }
            } catch { DispatchQueue.main.async { [weak self = self] in self?.alert(title + " failed", message: error.localizedDescription); self?.reload() } }
        }
    }
    private func pick(folder: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : [.item], asCopy: !folder)
        picker.allowsMultipleSelection = !folder; picker.delegate = self; presenter.present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let folder = urls.first, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if !granted.contains(folder), folder.startAccessingSecurityScopedResource() { granted.append(folder) }
            sidebar.reloadData(); navigate(folder); return
        }
        perform("Import") {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                var target = Workspace.documents.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) { target = Workspace.documents.appendingPathComponent(UUID().uuidString.prefix(6) + "-" + url.lastPathComponent) }
                try FileManager.default.copyItem(at: url, to: target)
            }
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { places.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "place") ?? UITableViewCell(style: .default, reuseIdentifier: "place")
        let place = places[indexPath.row]; cell.textLabel?.text = place.title; cell.textLabel?.font = .systemFont(ofSize: 12, weight: .medium); cell.imageView?.image = UIImage(systemName: place.symbol); cell.imageView?.tintColor = .systemTeal
        cell.backgroundColor = .clear; cell.accessoryType = place.url?.standardizedFileURL == current.standardizedFileURL ? .checkmark : .none; return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { if let url = places[indexPath.row].url { navigate(url) } else { showTrash() } }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { files.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "file", for: indexPath) as! FileItemCell
        cell.configure(files[indexPath.item], grid: gridMode); return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if !gridMode { return CGSize(width: max(1, collectionView.bounds.width - 16), height: 54) }
        let columns = max(1, floor((collectionView.bounds.width - 16) / 112))
        return CGSize(width: max(1, floor((collectionView.bounds.width - 16 - (columns - 1) * 8) / columns)), height: 108)
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets { UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat { gridMode ? 8 : 2 }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = files[indexPath.item]
        if item.isDirectory { navigate(item.url) } else { open(item.url) }
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let url = files[indexPath.item].url
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in UIMenu(children: self?.fileActions(url) ?? []) }
    }
    private func fileActions(_ url: URL) -> [UIAction] {
        [UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in self?.clipboard = (url, false); self?.footer.text = "Copied · choose a folder and Paste" },
         UIAction(title: "Cut", image: UIImage(systemName: "scissors")) { [weak self] _ in self?.clipboard = (url, true); self?.footer.text = "Cut · choose a folder and Paste" },
         UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.rename(url) },
         UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(url) },
         UIAction(title: FileOperations.contains(url, in: Workspace.documents) ? "Move to Trash" : "Delete permanently", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in self?.delete(url) }]
    }
    private func actions(_ url: URL) {
        let menu = UIAlertController(title: url.lastPathComponent, message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in self?.clipboard = (url, false) })
        menu.addAction(UIAlertAction(title: "Cut", style: .default) { [weak self] _ in self?.clipboard = (url, true) })
        menu.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in self?.rename(url) })
        menu.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in self?.share(url) })
        menu.addAction(UIAlertAction(title: FileOperations.contains(url, in: Workspace.documents) ? "Move to Trash" : "Delete permanently", style: .destructive) { [weak self] _ in self?.delete(url) }); showMenu(menu)
    }
    private func rename(_ url: URL) {
        ask("Rename", initial: url.lastPathComponent) { [weak self] name in
            self?.perform("Rename", action: { _ = try FileOperations.rename(url, to: name) }, completion: { [weak self = self] in self?.clearPreview() })
        }
    }
    private func paste() {
        guard let clipboard else { alert("Nothing to paste", message: "Select Copy or Cut from a file’s context menu first."); return }
        let folder = current
        perform("Paste", action: { _ = try FileOperations.paste(source: clipboard.url, into: folder, move: clipboard.move) }, completion: { [weak self] in if clipboard.move { self?.clipboard = nil } })
    }
    private func delete(_ url: URL) {
        let sandbox = FileOperations.contains(url, in: Workspace.documents)
        let confirm = UIAlertController(title: sandbox ? "Move to Trash?" : "Delete permanently?", message: sandbox ? "You can restore this item from Trash." : "This mounted-storage item cannot be restored by ExtendDesk.", preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.addAction(UIAlertAction(title: sandbox ? "Move to Trash" : "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }; let store = self.trash
            self.perform("Delete", action: { if sandbox { try store.trash(url) } else { try FileManager.default.removeItem(at: url) } }, completion: { [weak self = self] in self?.clearPreview() })
        }); presenter.present(confirm, animated: true)
    }
    private func showTrash() {
        let store = trash
        Self.work.async { [weak self] in
            do {
                let records = try store.records()
                DispatchQueue.main.async { [weak self = self] in
                    guard let self else { return }
                    let menu = UIAlertController(title: "Trash · Restore an item", message: records.isEmpty ? "Trash is empty." : "Original items are restored only if the destination is available.", preferredStyle: .actionSheet)
                    for record in records {
                        menu.addAction(UIAlertAction(title: record.name, style: .default) { [weak self = self] _ in self?.perform("Restore", action: { _ = try store.restore(record) }) })
                    }; self.showMenu(menu)
                }
            } catch { DispatchQueue.main.async { [weak self = self] in self?.alert("Cannot read Trash", message: error.localizedDescription) } }
        }
    }
    private func showMenu(_ menu: UIAlertController) {
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel)); menu.popoverPresentationController?.sourceView = presenter.view; menu.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 80, width: 1, height: 1); presenter.present(menu, animated: true)
    }
    private func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = presenter.view; sheet.popoverPresentationController?.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 80, width: 1, height: 1); presenter.present(sheet, animated: true)
    }
    private func clearPreview() {
        previewGeneration = UUID(); player?.pause(); player = nil; previewURL = nil
        previewChild?.willMove(toParent: nil); previewChild?.view.removeFromSuperview(); previewChild?.removeFromParent(); previewChild = nil
        preview.subviews.forEach { $0.removeFromSuperview() }; view.setNeedsLayout()
    }
    private func open(_ url: URL) {
        clearPreview(); previewURL = url
        if view.bounds.width > 0 && view.bounds.width < 620 {
            let controller = QLPreviewController(); controller.dataSource = self; presenter.present(controller, animated: true); return
        }
        let ext = url.pathExtension.lowercased(), generation = previewGeneration
        if ["mp4", "mov", "m4v", "mp3", "m4a", "wav"].contains(ext) {
            let controller = AVPlayerViewController(); let player = AVPlayer(url: url); self.player = player; controller.player = player
            attachPreview(controller); player.play()
        } else if ext == "pdf" {
            Self.previews.async { [weak self] in
                let document = PDFDocument(url: url)
                DispatchQueue.main.async { [weak self = self] in guard let self, self.previewGeneration == generation, let document else { return }; self.attachPreview(PDFToolController(document: document, name: url.deletingPathExtension().lastPathComponent)) }
            }
        } else if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
            Self.previews.async { [weak self] in
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true]
                let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
                let image = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }.map { UIImage(cgImage: $0) }
                DispatchQueue.main.async { [weak self = self] in guard let self, self.previewGeneration == generation else { return }; let imageView = UIImageView(image: image); imageView.contentMode = .scaleAspectFit; self.preview.addSubview(imageView); self.view.setNeedsLayout() }
            }
        } else if ["txt", "md", "json", "csv", "log", "swift", "html"].contains(ext) {
            Self.previews.async { [weak self] in
                let value: String
                do {
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    let data = try handle.read(upToCount: 2 * 1024 * 1024) ?? Data()
                    value = String(decoding: data, as: UTF8.self)
                } catch { value = error.localizedDescription }
                DispatchQueue.main.async { [weak self = self] in guard let self, self.previewGeneration == generation else { return }; let text = UITextView(); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 13, weight: .regular); text.text = value; self.preview.addSubview(text); self.footer.text = "Text preview · first 2 MiB"; self.view.setNeedsLayout() }
            }
        } else {
            let controller = QLPreviewController(); controller.dataSource = self; presenter.present(controller, animated: true)
            let label = UILabel(); label.text = "Document preview opened on device"; label.textAlignment = .center; label.numberOfLines = 0; preview.addSubview(label)
        }; view.setNeedsLayout()
    }
    private func attachPreview(_ controller: UIViewController) { addChild(controller); preview.addSubview(controller.view); controller.didMove(toParent: self); previewChild = controller; view.setNeedsLayout() }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewURL! as NSURL }
    override func pointerClick(at point: CGPoint, secondary: Bool) {
        if let index = collection.indexPathForItem(at: view.convert(point, to: collection)) {
            if secondary { actions(files[index.item].url) } else { collectionView(collection, didSelectItemAt: index) }; return
        }
        if let child = previewChild as? DesktopContent, preview.frame.contains(point) { child.pointerClick(at: view.convert(point, to: previewChild!.view), secondary: secondary); return }
        super.pointerClick(at: point, secondary: secondary)
    }
    override func pointerScroll(at point: CGPoint, delta: CGPoint) {
        if let child = previewChild as? DesktopContent, preview.frame.contains(point) { child.pointerScroll(at: view.convert(point, to: previewChild!.view), delta: delta) }
        else { super.pointerScroll(at: point, delta: delta) }
    }
}

private final class FileItemCell: UICollectionViewCell {
    private let icon = UIImageView()
    private let name = UILabel()
    private let detail = UILabel()
    private var grid = false
    override init(frame: CGRect) {
        super.init(frame: frame); contentView.addSubview(icon); contentView.addSubview(name); contentView.addSubview(detail)
        icon.contentMode = .scaleAspectFit; name.font = .systemFont(ofSize: 12, weight: .medium); detail.font = .systemFont(ofSize: 10); detail.textColor = .secondaryLabel
        contentView.layer.cornerRadius = 8
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(_ item: FileBrowserItem, grid: Bool) {
        self.grid = grid; icon.image = UIImage(systemName: item.symbol); icon.tintColor = item.isDirectory ? .systemTeal : .systemIndigo; name.text = item.name; detail.text = item.detail
        name.textAlignment = grid ? .center : .left; name.numberOfLines = grid ? 2 : 1; detail.textAlignment = grid ? .center : .left; setNeedsLayout()
    }
    override var isSelected: Bool { didSet { contentView.backgroundColor = isSelected ? UIColor.systemTeal.withAlphaComponent(0.18) : .clear } }
    override func layoutSubviews() {
        super.layoutSubviews()
        if grid { icon.frame = CGRect(x: (bounds.width - 38) / 2, y: 8, width: 38, height: 38); name.frame = CGRect(x: 4, y: 50, width: bounds.width - 8, height: 34); detail.frame = CGRect(x: 4, y: 86, width: bounds.width - 8, height: 16) }
        else { icon.frame = CGRect(x: 10, y: 12, width: 28, height: 28); name.frame = CGRect(x: 48, y: 7, width: bounds.width - 56, height: 22); detail.frame = CGRect(x: 48, y: 30, width: bounds.width - 56, height: 16) }
    }
}

final class NotesController: ToolController, UITextViewDelegate {
    private let text = UITextView()
    private let toolbar = UIStackView()
    private let id: UUID
    private var file: URL
    private let writer = BufferedTextWriter()
    private var backgroundObserver: NSObjectProtocol?
    init(id: UUID) {
        self.id = id
        let directory = Workspace.documents.appendingPathComponent("Notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let name = UserDefaults.standard.string(forKey: "note.\(id)") {
            file = directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        } else { file = directory.appendingPathComponent("\(id.uuidString).txt") }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        text.font = .systemFont(ofSize: 18); text.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        text.text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""; text.delegate = self
        toolbar.axis = .horizontal
        toolbar.addArrangedSubview(actionButton("square.and.pencil", title: "Edit on device") { [weak self] in self?.editOnDevice() })
        toolbar.addArrangedSubview(actionButton("folder", title: "Open") { [weak self] in self?.openNote() })
        toolbar.addArrangedSubview(actionButton("pencil", title: "Rename") { [weak self] in self?.renameNote() })
        view.addSubview(toolbar); view.addSubview(text)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.writer.flush() }
    }
    deinit { if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }; writer.flush() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); toolbar.frame = CGRect(x: 8, y: 0, width: view.bounds.width - 16, height: 44); text.frame = CGRect(x: 0, y: 44, width: view.bounds.width, height: max(0, view.bounds.height - 44)) }
    func textViewDidChange(_ textView: UITextView) { writer.schedule(textView.text, to: file) { [weak self] error in self?.alert("Save failed", message: error.localizedDescription) } }
    override func insertText(_ value: String) { guard text.isEditable else { return }; if value == "\u{8}" { text.deleteBackward() } else { text.insertText(value) }; textViewDidChange(text) }
    private func editOnDevice() {
        let editor = NoteEditor(text: text.text) { [weak self] value in self?.text.text = value; if let self { self.textViewDidChange(self.text) } }
        presenter.present(UINavigationController(rootViewController: editor), animated: true)
    }
    private func openNote() {
        let files = (try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        let alert = UIAlertController(title: "Open note", message: nil, preferredStyle: .actionSheet)
        for url in files.filter({ $0.pathExtension == "txt" }) {
            alert.addAction(UIAlertAction(title: url.deletingPathExtension().lastPathComponent, style: .default) { [weak self] _ in
                guard let self else { return }
                self.text.isEditable = false; self.toolbar.isUserInteractionEnabled = false
                self.writer.flush { [weak self = self] result in
                    guard let self else { return }; defer { self.text.isEditable = true; self.toolbar.isUserInteractionEnabled = true }
                    guard case .success = result else { return }
                    self.file = url; UserDefaults.standard.set(url.lastPathComponent, forKey: "note.\(self.id)"); self.text.text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                }
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)); alert.popoverPresentationController?.sourceView = presenter.view; alert.popoverPresentationController?.sourceRect = CGRect(x: 30, y: 60, width: 1, height: 1); presenter.present(alert, animated: true)
    }
    private func renameNote() {
        ask("Note name", initial: file.deletingPathExtension().lastPathComponent) { [weak self] name in
            guard let self, !name.contains("/"), name != ".", name != ".." else { return }
            let target = self.file.deletingLastPathComponent().appendingPathComponent(name + ".txt")
            self.text.isEditable = false; self.toolbar.isUserInteractionEnabled = false
            self.writer.flush { [weak self = self] result in
                guard let self else { return }; defer { self.text.isEditable = true; self.toolbar.isUserInteractionEnabled = true }
                guard case .success = result else { return }
                do {
                    if FileManager.default.fileExists(atPath: self.file.path) { try FileManager.default.moveItem(at: self.file, to: target) }
                    else { try self.text.text.write(to: target, atomically: true, encoding: .utf8) }
                    self.file = target; UserDefaults.standard.set(target.lastPathComponent, forKey: "note.\(self.id)")
                    Workspace.shared.update(self.id) { $0.title = name }; NotificationCenter.default.post(name: Notification.Name("filesChanged"), object: nil)
                } catch { self.alert("Rename failed", message: error.localizedDescription) }
            }
        }
    }
}

final class PDFToolController: ToolController {
    private let pdf = PDFView()
    private let toolbar = UIStackView()
    private let document: PDFDocument
    private let name: String
    init(document: PDFDocument, name: String) { self.document = document; self.name = name; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); pdf.document = document; pdf.autoScales = true
        toolbar.axis = .horizontal
        toolbar.addArrangedSubview(actionButton("chevron.left", title: nil) { [weak self] in self?.pdf.goToPreviousPage(nil) })
        toolbar.addArrangedSubview(actionButton("chevron.right", title: nil) { [weak self] in self?.pdf.goToNextPage(nil) })
        toolbar.addArrangedSubview(actionButton("note.text.badge.plus", title: "Note") { [weak self] in self?.addNote() })
        toolbar.addArrangedSubview(actionButton("square.and.arrow.down", title: "Save copy") { [weak self] in self?.saveCopy() })
        view.addSubview(toolbar); view.addSubview(pdf)
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); toolbar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 44); pdf.frame = CGRect(x: 0, y: 44, width: view.bounds.width, height: max(0, view.bounds.height - 44)) }
    private func addNote() {
        guard let page = pdf.currentPage else { return }
        ask("Add a note to this page") { [weak self] value in
            guard let self else { return }
            let bounds = page.bounds(for: .mediaBox)
            let annotation = PDFAnnotation(bounds: CGRect(x: bounds.minX + 30, y: bounds.maxY - 60, width: 28, height: 28), forType: .text, withProperties: nil)
            annotation.contents = value; annotation.color = .systemYellow; page.addAnnotation(annotation); self.pdf.setNeedsDisplay()
        }
    }
    private func saveCopy() {
        let url = Workspace.downloads.appendingPathComponent(name + "-annotated-" + UUID().uuidString.prefix(6) + ".pdf")
        if document.write(to: url) { alert("Saved", message: url.lastPathComponent + " in Downloads") }
        else { alert("Could not save PDF") }
    }
}

final class NoteEditor: UIViewController {
    private let editor = UITextView()
    private let initial: String
    private let onSave: (String) -> Void
    init(text: String, onSave: @escaping (String) -> Void) { initial = text; self.onSave = onSave; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = "Notes"; editor.text = initial; editor.font = .systemFont(ofSize: 18); view.addSubview(editor)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .done, target: self, action: #selector(save))
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); editor.frame = view.bounds.inset(by: view.safeAreaInsets) }
    @objc private func save() { onSave(editor.text); dismiss(animated: true) }
    @objc private func cancel() { dismiss(animated: true) }
}

struct CalculatorEngine {
    private(set) var display = "0"
    private var accumulator: Double?
    private var operation: String?
    private var fresh = true
    mutating func press(_ key: String) {
        if key == "C" { self = CalculatorEngine(); return }
        if key == "±" { if let number = Double(display) { display = format(-number) }; return }
        if key == "%" { if let number = Double(display) { display = format(number / 100) }; return }
        if ["+", "−", "×", "÷", "="].contains(key) {
            if let a = accumulator, let op = operation, let b = Double(display), !fresh {
                switch op {
                case "+": display = format(a + b)
                case "−": display = format(a - b)
                case "×": display = format(a * b)
                default: display = b == 0 ? "Error" : format(a / b)
                }
            }
            accumulator = Double(display); operation = key == "=" ? nil : key; fresh = true; return
        }
        if fresh || display == "Error" { display = key == "." ? "0." : key; fresh = false }
        else if key != "." || !display.contains(".") { display = display == "0" && key != "." ? key : display + key }
    }
    private func format(_ number: Double) -> String { number.isFinite ? String(format: "%.12g", number) : "Error" }
}

final class CalculatorController: ToolController {
    private var engine = CalculatorEngine()
    private let display = UILabel()
    private let stack = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        display.font = .monospacedDigitSystemFont(ofSize: 44, weight: .light); display.textAlignment = .right; display.textColor = .white; display.text = engine.display
        stack.axis = .vertical; stack.spacing = 6; stack.distribution = .fillEqually
        for keys in [["C", "±", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "−"], ["1", "2", "3", "+"], ["0", ".", "="]] {
            let row = UIStackView(); row.spacing = 6; row.distribution = .fillEqually
            for key in keys {
                let button = UIButton(type: .system); button.setTitle(key, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 26)
                button.backgroundColor = Double(key) != nil || key == "." ? .darkGray : .systemOrange; button.tintColor = .white; button.layer.cornerRadius = 12
                button.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchUpInside); row.addArrangedSubview(button)
            }; stack.addArrangedSubview(row)
        }; view.addSubview(display); view.addSubview(stack)
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); display.frame = CGRect(x: 16, y: 4, width: view.bounds.width - 32, height: 64); stack.frame = CGRect(x: 12, y: 76, width: view.bounds.width - 24, height: max(0, view.bounds.height - 88)) }
    private func press(_ key: String) { engine.press(key); display.text = engine.display }
    override func insertText(_ text: String) { for char in text { let key = String(char); if "0123456789.+−×÷=%".contains(key) { press(key) } } }
}

