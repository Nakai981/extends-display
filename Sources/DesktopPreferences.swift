import UIKit
import ImageIO

extension Notification.Name {
    static let appearanceChanged = Notification.Name("appearanceChanged")
}

enum DesktopAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { rawValue.capitalized }
    var interfaceStyle: UIUserInterfaceStyle {
        switch self { case .system: return .unspecified; case .light: return .light; case .dark: return .dark }
    }
}

enum DesktopAccent: String, CaseIterable {
    case blue, purple, pink, orange, green, teal
    var title: String { rawValue.capitalized }
    var color: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .teal: return .systemTeal
        }
    }
}

enum WallpaperImportError: LocalizedError {
    case unsupportedImage, cannotEncode
    var errorDescription: String? {
        switch self {
        case .unsupportedImage: return "This file could not be opened as an image. Choose a JPEG, PNG, HEIC or another supported image."
        case .cannotEncode: return "The selected image could not be saved as a wallpaper."
        }
    }
}

/// Main-thread preferences. Wallpaper decoding and file writes run on a separate queue.
final class DesktopPreferences {
    static let shared = DesktopPreferences()
    static let wallpaperTitles = ["Highlands", "Coast", "Dusk", "Graphite"]
    private let defaults: UserDefaults
    private let directory: URL
    private let images = DispatchQueue(label: "extenddesk.wallpaper", qos: .userInitiated)
    private var imageRequest = UUID()
    private var imageLoading = false
    private var imageCallbacks: [(UIImage?) -> Void] = []
    private var notificationPending = false
    private(set) var customWallpaperImage: UIImage?

    init(defaults: UserDefaults = .standard, storageDirectory: URL? = nil) {
        self.defaults = defaults
        self.directory = storageDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Appearance", isDirectory: true)
    }
    var appearance: DesktopAppearance {
        get { DesktopAppearance(rawValue: defaults.string(forKey: "appearance.style") ?? "") ?? .dark }
        set { set(newValue.rawValue, for: "appearance.style") }
    }
    var accent: DesktopAccent {
        get { DesktopAccent(rawValue: defaults.string(forKey: "appearance.accent") ?? "") ?? .blue }
        set { set(newValue.rawValue, for: "appearance.accent") }
    }
    var wallpaperPreset: Int {
        get {
            let value = defaults.object(forKey: "appearance.wallpaper") == nil ? defaults.integer(forKey: "wallpaper") : defaults.integer(forKey: "appearance.wallpaper")
            return min(Self.wallpaperTitles.count - 1, max(0, value))
        }
        set { set(min(Self.wallpaperTitles.count - 1, max(0, newValue)), for: "appearance.wallpaper") }
    }
    var dockAutoHide: Bool {
        get { defaults.bool(forKey: "appearance.dockAutoHide") }
        set { set(newValue, for: "appearance.dockAutoHide") }
    }
    var reduceMotion: Bool {
        get { defaults.bool(forKey: "appearance.reduceMotion") }
        set { set(newValue, for: "appearance.reduceMotion") }
    }
    var effectiveReduceMotion: Bool { reduceMotion || UIAccessibility.isReduceMotionEnabled }
    var dockSize: CGFloat {
        get {
            let value = defaults.double(forKey: "appearance.dockSize")
            return value.isFinite && value > 0 ? CGFloat(min(64, max(36, value))) : 44
        }
        set { set(newValue.isFinite ? Double(min(64, max(36, newValue))) : 44, for: "appearance.dockSize") }
    }
    var interfaceStyle: UIUserInterfaceStyle { appearance.interfaceStyle }
    var customWallpaperURL: URL? {
        guard let name = defaults.string(forKey: "appearance.wallpaperFile"),
              name == URL(fileURLWithPath: name).lastPathComponent,
              name.hasPrefix("wallpaper-"), name.hasSuffix(".jpg") else { return nil }
        return directory.appendingPathComponent(name)
    }
    var hasCustomWallpaper: Bool { customWallpaperURL != nil }

    private func set(_ value: Any, for key: String) {
        defaults.set(value, forKey: key); changed()
    }
    private func changed() {
        guard !notificationPending else { return }; notificationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.notificationPending = false
            NotificationCenter.default.post(name: .appearanceChanged, object: self)
        }
    }
    /// A scoped URL is leased before leaving the picker callback. Decoding is bounded to 2560 pixels.
    func importWallpaper(from url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let request = UUID(); imageRequest = request; imageLoading = false
        let scoped = url.startAccessingSecurityScopedResource(), directory = self.directory
        images.async { [weak self] in
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2560, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw WallpaperImportError.unsupportedImage }
                let thumbnail = UIImage(cgImage: image)
                guard let data = thumbnail.jpegData(compressionQuality: 0.88) else { throw WallpaperImportError.cannotEncode }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent("wallpaper-" + request.uuidString + ".jpg")
                try data.write(to: destination, options: .atomic)
                DispatchQueue.main.async { [weak self = self] in
                    guard let self, self.imageRequest == request else {
                        try? FileManager.default.removeItem(at: destination)
                        completion(.failure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))); return
                    }
                    let previous = self.customWallpaperURL
                    self.defaults.set(destination.lastPathComponent, forKey: "appearance.wallpaperFile")
                    self.customWallpaperImage = thumbnail; self.imageLoading = false
                    let waiting = self.imageCallbacks; self.imageCallbacks.removeAll(); waiting.forEach { $0(thumbnail) }
                    self.changed(); completion(.success(Void()))
                    if let previous, previous != destination { self.images.async { try? FileManager.default.removeItem(at: previous) } }
                }
            } catch {
                DispatchQueue.main.async { [weak self = self] in
                    if let self, self.imageRequest == request {
                        // A refresh may already be loading the previous wallpaper.
                        // Keep that job's callbacks intact; otherwise restart the
                        // load invalidated when this import began.
                        if !self.imageLoading, !self.imageCallbacks.isEmpty {
                            let waiting = self.imageCallbacks; self.imageCallbacks.removeAll()
                            self.loadCustomWallpaper { image in waiting.forEach { $0(image) } }
                        }
                    }
                    completion(.failure(error))
                }
            }
        }
    }
    func loadCustomWallpaper(completion: @escaping (UIImage?) -> Void) {
        if let customWallpaperImage { completion(customWallpaperImage); return }
        guard let url = customWallpaperURL else { completion(nil); return }
        imageCallbacks.append(completion)
        guard !imageLoading else { return }; imageLoading = true
        let request = imageRequest
        images.async { [weak self] in
            let image = UIImage(contentsOfFile: url.path)
            DispatchQueue.main.async { [weak self = self] in
                guard let self, self.imageRequest == request, self.customWallpaperURL == url else { return }
                self.customWallpaperImage = image; self.imageLoading = false
                let callbacks = self.imageCallbacks; self.imageCallbacks.removeAll(); callbacks.forEach { $0(image) }
            }
        }
    }
    func clearCustomWallpaper() {
        let previous = customWallpaperURL
        imageRequest = UUID(); imageLoading = false; customWallpaperImage = nil
        defaults.removeObject(forKey: "appearance.wallpaperFile")
        let callbacks = imageCallbacks; imageCallbacks.removeAll(); callbacks.forEach { $0(nil) }
        changed()
        if let previous { images.async { try? FileManager.default.removeItem(at: previous) } }
    }
    func resetAppearance() {
        clearCustomWallpaper()
        for key in ["appearance.style", "appearance.accent", "appearance.wallpaper", "appearance.dockAutoHide", "appearance.reduceMotion", "appearance.dockSize"] { defaults.removeObject(forKey: key) }
        // Retain an explicit default so legacy `wallpaper` values cannot
        // reappear through the migration fallback after reset.
        defaults.set(0, forKey: "appearance.wallpaper")
        changed()
    }
}

enum DesktopStyle {
    static var surface: UIColor { UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 0.97) : UIColor(white: 0.97, alpha: 0.97) } }
    static var border: UIColor { UIColor { $0.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.14) : UIColor.black.withAlphaComponent(0.12) } }
    static var accent: UIColor { DesktopPreferences.shared.accent.color }
    static var text: UIColor { .label }
    static var secondaryText: UIColor { .secondaryLabel }
    static var menuForeground: UIColor { .white }
    static var desktopTitle: UIColor { .white }
    static let headerHeight: CGFloat = 36
}
