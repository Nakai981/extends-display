import XCTest
@testable import ExtendDesk

final class CoreTests: XCTestCase {
    func testAddressesAndSearchEncoding() {
        XCTAssertEqual(Address.resolve(" example.com/path ")?.absoluteString, "https://example.com/path")
        XCTAssertEqual(Address.resolve("https://example.com/a?q=1")?.host, "example.com")
        XCTAssertNil(Address.resolve("  "))
        let search = Address.resolve("swift & ios")!
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "swift & ios")
        XCTAssertEqual(Address.resolve("javascript:alert(1)")?.scheme, "https")
    }
    func testSessionRoundTrip() throws {
        var original = WindowRecord(kind: .browser, title: "Example", url: "https://example.com")
        original.setFrame(CGRect(x: 12, y: 24, width: 640, height: 480)); original.minimized = true
        let restored = try JSONDecoder().decode(WindowRecord.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.id, original.id); XCTAssertEqual(restored.frame, original.frame)
        XCTAssertTrue(restored.minimized); XCTAssertEqual(restored.url, original.url)
    }
    func testCalculatorChainingAndZeroDivision() {
        var calc = CalculatorEngine()
        ["2", "+", "3", "×", "4", "="].forEach { calc.press($0) }
        XCTAssertEqual(calc.display, "20")
        ["C", "8", "÷", "0", "="].forEach { calc.press($0) }
        XCTAssertEqual(calc.display, "Error")
        calc.press("7"); XCTAssertEqual(calc.display, "7")
    }
    func testCalculatorDecimalsAndSign() {
        var calc = CalculatorEngine()
        [".", "5", ".", "±", "%"].forEach { calc.press($0) }
        XCTAssertEqual(calc.display, "-0.005")
    }
}
