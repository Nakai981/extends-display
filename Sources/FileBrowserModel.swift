import Foundation

struct FileBrowserItem: Equatable {
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    var name: String { url.lastPathComponent }
    var detail: String {
        isDirectory ? "Folder" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    var symbol: String {
        if isDirectory { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "mp4", "mov", "m4v": return "film"
        case "mp3", "m4a", "wav": return "waveform"
        case "zip": return "doc.zipper"
        default: return "doc.text"
        }
    }
}

enum FileSortOrder: Int, CaseIterable {
    case name, modified, size
    var title: String { ["Name", "Date modified", "Size"][rawValue] }
    func sorted(_ items: [FileBrowserItem]) -> [FileBrowserItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch self {
            case .modified: if a.modified != b.modified { return a.modified > b.modified }
            case .size: if a.size != b.size { return a.size > b.size }
            case .name: break
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// One directory load at a time. Superseded requests never apply stale UI results.
final class DirectoryLoader {
    private let queue = DispatchQueue(label: "extenddesk.directory", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = UUID()
    func cancel() { lock.lock(); generation = UUID(); lock.unlock() }
    private func isCurrent(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == id }
    func load(_ directory: URL, sort: FileSortOrder, completion: @escaping (Result<[FileBrowserItem], Error>) -> Void) {
        let id = UUID(); lock.lock(); generation = id; lock.unlock()
        queue.async { [weak self] in
            guard let self, self.isCurrent(id) else { return }
            let result: Result<[FileBrowserItem], Error>
            do {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
                let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                var items: [FileBrowserItem] = []; items.reserveCapacity(urls.count)
                for url in urls {
                    guard self.isCurrent(id) else { return }
                    let values = try? url.resourceValues(forKeys: keys)
                    items.append(FileBrowserItem(url: url, isDirectory: values?.isDirectory ?? false, size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast))
                }
                result = .success(sort.sorted(items))
            } catch { result = .failure(error) }
            DispatchQueue.main.async { [weak self = self] in guard self?.isCurrent(id) == true else { return }; completion(result) }
        }
    }
}

enum FileOperationError: LocalizedError {
    case invalidName, invalidDestination, destinationExists, outsideSandbox, missingTrashItem
    var errorDescription: String? {
        switch self {
        case .invalidName: return "Choose a name without slash, colon, or dot-only components."
        case .invalidDestination: return "A folder cannot be pasted into itself or one of its subfolders."
        case .destinationExists: return "An item with this name already exists. Rename it or choose another folder."
        case .outsideSandbox: return "This action is limited to the app's own Documents folder."
        case .missingTrashItem: return "The selected item is no longer in Trash."
        }
    }
}

enum FileOperations {
    static let queue = DispatchQueue(label: "extenddesk.files.operations", qos: .userInitiated)
    static func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":") && !name.contains("\0")
    }
    static func contains(_ item: URL, in root: URL) -> Bool {
        let root = root.standardizedFileURL.resolvingSymlinksInPath().path
        let item = item.standardizedFileURL.resolvingSymlinksInPath().path
        return item == root || item.hasPrefix(root + "/")
    }
    static func paste(source: URL, into folder: URL, move: Bool, manager: FileManager = .default) throws -> URL {
        let source = source.standardizedFileURL
        let destination = folder.appendingPathComponent(source.lastPathComponent).standardizedFileURL
        guard !contains(destination, in: source) else { throw FileOperationError.invalidDestination }
        guard !manager.fileExists(atPath: destination.path) else { throw FileOperationError.destinationExists }
        if move { try manager.moveItem(at: source, to: destination) }
        else { try manager.copyItem(at: source, to: destination) }
        return destination
    }
    static func rename(_ url: URL, to name: String, manager: FileManager = .default) throws -> URL {
        guard validName(name) else { throw FileOperationError.invalidName }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        if destination.standardizedFileURL == url.standardizedFileURL { return url }
        guard !manager.fileExists(atPath: destination.path) else { throw FileOperationError.destinationExists }
        try manager.moveItem(at: url, to: destination); return destination
    }
}

struct TrashedFile: Codable, Identifiable {
    let id: UUID
    let name: String
    let relativeOriginalPath: String
    let deleted: Date
}

/// App-owned Trash. Mounted external storage retains an explicit permanent-delete flow.
final class FileTrashStore {
    let root: URL
    var directory: URL { root.appendingPathComponent(".ExtendDeskTrash", isDirectory: true) }
    private var manifest: URL { directory.appendingPathComponent("index.json") }
    init(root: URL) { self.root = root.standardizedFileURL }
    func records() throws -> [TrashedFile] {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return [] }
        return try JSONDecoder().decode([TrashedFile].self, from: Data(contentsOf: manifest)).sorted { $0.deleted > $1.deleted }
    }
    func trash(_ url: URL) throws {
        guard FileOperations.contains(url, in: root), url.standardizedFileURL != root,
              !FileOperations.contains(url, in: directory) else { throw FileOperationError.outsideSandbox }
        let rootPath = root.standardizedFileURL.path
        let originalPath = url.standardizedFileURL.path
        guard originalPath.hasPrefix(rootPath + "/") else { throw FileOperationError.outsideSandbox }
        let relative = String(originalPath.dropFirst(rootPath.count + 1))
        let record = TrashedFile(id: UUID(), name: url.lastPathComponent, relativeOriginalPath: relative, deleted: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var all = try records()
        let stored = directory.appendingPathComponent(record.id.uuidString)
        try FileManager.default.moveItem(at: url, to: stored)
        all.append(record)
        do { try write(all) }
        catch { try? FileManager.default.moveItem(at: stored, to: url); throw error }
    }
    @discardableResult func restore(_ record: TrashedFile) throws -> URL {
        let source = directory.appendingPathComponent(record.id.uuidString)
        guard FileManager.default.fileExists(atPath: source.path) else { throw FileOperationError.missingTrashItem }
        let destination = root.appendingPathComponent(record.relativeOriginalPath).standardizedFileURL
        guard FileOperations.contains(destination, in: root), destination != root,
              !FileOperations.contains(destination, in: directory) else { throw FileOperationError.outsideSandbox }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw FileOperationError.destinationExists }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var all = try records(); all.removeAll { $0.id == record.id }
        try FileManager.default.moveItem(at: source, to: destination)
        do { try write(all) }
        catch { try? FileManager.default.moveItem(at: destination, to: source); throw error }
        return destination
    }
    private func write(_ records: [TrashedFile]) throws { try JSONEncoder().encode(records).write(to: manifest, options: .atomic) }
}
