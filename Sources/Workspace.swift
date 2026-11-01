import UIKit

enum AppKind: String, Codable, CaseIterable {
    case browser, files, photos, notes, calculator, settings
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .browser: return "globe"
        case .files: return "folder.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .notes: return "note.text"
        case .calculator: return "plus.forwardslash.minus"
        case .settings: return "gearshape.fill"
        }
    }
}

struct WindowRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: AppKind
    var title: String
    var url: String?
    var x: Double = 80
    var y: Double = 70
    var width: Double = 800
    var height: Double = 540
    var minimized = false
    var maximized = false
    var restoreFrame: CGRect?
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    mutating func setFrame(_ frame: CGRect) {
        x = frame.origin.x; y = frame.origin.y; width = frame.width; height = frame.height
    }
}

struct Bookmark: Codable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
}

enum Address {
    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) { return url }
        if !text.contains(" "), text.contains("."), !text.contains("://") {
            return URL(string: "https://" + text)
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}

final class Workspace {
    static let shared = Workspace()
    weak var externalDesktop: DesktopController?
    weak var localDesktop: DesktopController?
    var activeDesktop: DesktopController? { externalDesktop ?? localDesktop }
    private(set) var windows: [WindowRecord] = []
    private(set) var bookmarks: [Bookmark] = []
    private(set) var desktopRevealed = false
    private var contentControllers: [UUID: UIViewController] = [:]
    private var pendingSave: DispatchWorkItem?
    private var notificationPending = false
    private let defaults: UserDefaults
    var focusedID: UUID?
    var wallpaper: Int {
        didSet { guard wallpaper != oldValue else { return }; defaults.set(wallpaper, forKey: "wallpaper"); changed() }
    }
    var pointerSpeed: Double {
        get { let value = defaults.double(forKey: "pointerSpeed"); return value == 0 ? 1.5 : value }
        set { defaults.set(min(4, max(0.3, newValue)), forKey: "pointerSpeed") }
    }
    static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var downloads: URL {
        let url = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var desktopFolder: URL {
        let url = documents.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; wallpaper = defaults.integer(forKey: "wallpaper")
        if let data = defaults.data(forKey: "windows"),
           let saved = try? JSONDecoder().decode([WindowRecord].self, from: data) { windows = saved }
        if let data = defaults.data(forKey: "bookmarks"),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) { bookmarks = saved }
        focusedID = windows.last(where: { !$0.minimized })?.id
    }
    @discardableResult func open(_ kind: AppKind, url: String? = nil) -> UUID {
        desktopRevealed = false
        let offset = Double(windows.count % 7) * 26
        var record = WindowRecord(kind: kind, title: kind.title, url: url)
        record.x += offset; record.y += offset
        windows.append(record); focusedID = record.id; changed()
        return record.id
    }
    func focus(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        guard desktopRevealed || focusedID != id || windows[index].minimized || index != windows.count - 1 else { return }
        desktopRevealed = false
        var item = windows.remove(at: index); item.minimized = false
        windows.append(item); focusedID = id; changed()
    }
    func update(_ id: UUID, notify: Bool = true, _ edit: (inout WindowRecord) -> Void) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        let previous = windows[index]
        edit(&windows[index])
        guard previous != windows[index] else { return }
        if windows[index].minimized && focusedID == id { focusedID = windows.last(where: { !$0.minimized })?.id }
        if notify { changed() }
    }
    func close(_ id: UUID) {
        windows.removeAll { $0.id == id }
        contentControllers.removeValue(forKey: id)
        defaults.removeObject(forKey: "browser.session.\(id)")
        if focusedID == id { focusedID = windows.last(where: { !$0.minimized })?.id }
        changed()
    }
    func pin(title: String, url: String) {
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.append(Bookmark(title: title, url: url)); changed()
    }
    func unpin(_ id: UUID) { bookmarks.removeAll { $0.id == id }; changed() }
    func changed() {
        pendingSave?.cancel()
        let save = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = save; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: save)
        guard !notificationPending else { return }
        notificationPending = true
        DispatchQueue.main.async { [weak self] in
            self?.notificationPending = false
            if let self { NotificationCenter.default.post(name: .workspaceChanged, object: self) }
        }
    }
    func save() {
        pendingSave?.cancel(); pendingSave = nil
        if let data = try? JSONEncoder().encode(windows) { defaults.set(data, forKey: "windows") }
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: "bookmarks") }
    }
    @discardableResult func activate(_ kind: AppKind) -> UUID {
        if let record = windows.last(where: { $0.kind == kind }) { focus(record.id); return record.id }
        return open(kind)
    }
    func cycleWindow() {
        let visible = windows.filter { !$0.minimized }
        guard visible.count > 1 else { return }
        focus(visible[0].id)
    }
    func toggleDesktop() { desktopRevealed.toggle(); changed() }
    @MainActor func content(for record: WindowRecord) -> UIViewController {
        if let existing = contentControllers[record.id] { return existing }
        let controller: UIViewController
        switch record.kind {
        case .browser: controller = BrowserController(id: record.id, url: record.url)
        case .files: controller = FilesController(initialURL: record.url.flatMap(URL.init(string:)))
        case .photos: controller = PhotosController()
        case .notes: controller = NotesController(id: record.id)
        case .calculator: controller = CalculatorController()
        case .settings: controller = SystemSettingsController()
        }
        contentControllers[record.id] = controller
        return controller
    }
}
