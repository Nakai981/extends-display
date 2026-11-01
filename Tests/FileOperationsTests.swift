import XCTest
@testable import ExtendDesk

final class FileOperationsTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func testPasteRejectsDescendantAndDoesNotOverwrite() throws {
        let source = directory.appendingPathComponent("Source", isDirectory: true)
        let child = source.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        XCTAssertThrowsError(try FileOperations.paste(source: source, into: child, move: false))
        let target = directory.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("Source"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try FileOperations.paste(source: source, into: target, move: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testTrashRestoreAndConflictPreserveContents() throws {
        let file = directory.appendingPathComponent("Original.txt")
        try Data("first".utf8).write(to: file)
        let trash = FileTrashStore(root: directory)
        try trash.trash(file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let record = try XCTUnwrap(trash.records().first)
        try Data("replacement".utf8).write(to: file)
        XCTAssertThrowsError(try trash.restore(record))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "replacement")
        XCTAssertEqual(try trash.records().count, 1)
        try FileManager.default.removeItem(at: file)
        let restored = try trash.restore(record)
        XCTAssertEqual(try String(contentsOf: restored, encoding: .utf8), "first")
        XCTAssertTrue(try trash.records().isEmpty)
    }
    func testTrashRejectsPathsOutsideRoot() throws {
        let outside = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".txt")
        try Data("outside".utf8).write(to: outside); defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertThrowsError(try FileTrashStore(root: directory).trash(outside))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testRestoreRejectsForgedTraversalRecord() throws {
        let trash = FileTrashStore(root: directory)
        try FileManager.default.createDirectory(at: trash.directory, withIntermediateDirectories: true)
        let forged = TrashedFile(id: UUID(), name: "escape", relativeOriginalPath: "../escape.txt", deleted: Date())
        try Data("test".utf8).write(to: trash.directory.appendingPathComponent(forged.id.uuidString))
        XCTAssertThrowsError(try trash.restore(forged))
    }
    func testNamesAndSortOrder() {
        XCTAssertFalse(FileOperations.validName("../unsafe")); XCTAssertFalse(FileOperations.validName("..")); XCTAssertTrue(FileOperations.validName("Ghi chú.txt"))
        let items = [FileBrowserItem(url: directory.appendingPathComponent("z.txt"), isDirectory: false, size: 10, modified: .distantPast), FileBrowserItem(url: directory.appendingPathComponent("Folder"), isDirectory: true, size: 0, modified: .distantPast)]
        XCTAssertEqual(FileSortOrder.name.sorted(items).first?.name, "Folder")
    }
    func testBufferedWriterFlushesLatestSnapshot() {
        let file = directory.appendingPathComponent("Note.txt")
        let writer = BufferedTextWriter()
        let saved = expectation(description: "Latest note snapshot flushed")
        writer.schedule("old", to: file) { error in XCTFail(error.localizedDescription) }
        writer.schedule("new tiếng Việt", to: file) { error in XCTFail(error.localizedDescription) }
        writer.flush { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            XCTAssertEqual(try? String(contentsOf: file, encoding: .utf8), "new tiếng Việt")
            saved.fulfill()
        }
        wait(for: [saved], timeout: 2)
    }
}
