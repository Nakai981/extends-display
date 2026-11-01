import XCTest
@testable import ExtendDesk

final class PreferencesTests: XCTestCase {
    func testPreferencesPersistAndClampInvalidValues() {
        let name = "ExtendDeskPreferencesTests.\(UUID())", directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = DesktopPreferences(defaults: defaults, storageDirectory: directory)
        preferences.appearance = .light; preferences.accent = .teal; preferences.dockAutoHide = true
        preferences.dockSize = 100; preferences.wallpaperPreset = -12; preferences.reduceMotion = true
        let restored = DesktopPreferences(defaults: defaults, storageDirectory: directory)
        XCTAssertEqual(restored.appearance, .light); XCTAssertEqual(restored.accent, .teal)
        XCTAssertTrue(restored.dockAutoHide); XCTAssertTrue(restored.reduceMotion)
        XCTAssertEqual(restored.dockSize, 64); XCTAssertEqual(restored.wallpaperPreset, 0)
        defaults.set("../outside.jpg", forKey: "appearance.wallpaperFile")
        XCTAssertNil(restored.customWallpaperURL)
        defaults.set("unknown-style", forKey: "appearance.style")
        XCTAssertEqual(restored.appearance, .dark)
    }
    func testResetRestoresDefaultAppearanceAndDoesNotChangeUnrelatedData() {
        let name = "ExtendDeskPreferencesTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("keep", forKey: "unrelated")
        defaults.set(2, forKey: "wallpaper")
        let preferences = DesktopPreferences(defaults: defaults)
        XCTAssertEqual(preferences.wallpaperPreset, 2)
        preferences.appearance = .light; preferences.dockSize = 60
        preferences.resetAppearance()
        XCTAssertEqual(preferences.appearance, .dark); XCTAssertEqual(preferences.dockSize, 44)
        XCTAssertEqual(preferences.wallpaperPreset, 0)
        XCTAssertEqual(DesktopPreferences(defaults: defaults).wallpaperPreset, 0)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }
    func testInvalidWallpaperImportKeepsPreviousSelection() throws {
        let name = "ExtendDeskPreferencesTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        defaults.set("wallpaper-previous.jpg", forKey: "appearance.wallpaperFile")
        let invalid = directory.appendingPathComponent("invalid.txt")
        try Data("not an image".utf8).write(to: invalid)
        let preferences = DesktopPreferences(defaults: defaults, storageDirectory: directory)
        let completed = expectation(description: "Invalid import rejected")
        preferences.importWallpaper(from: invalid) { result in
            if case .success = result { XCTFail("Invalid image was accepted") }
            XCTAssertEqual(preferences.customWallpaperURL?.lastPathComponent, "wallpaper-previous.jpg")
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)
    }
}
