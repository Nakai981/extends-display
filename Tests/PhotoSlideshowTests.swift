import XCTest
@testable import ExtendDesk

final class PhotoSlideshowTests: XCTestCase {
    func testEmptyLibraryCannotPlayAndLibraryChangesClampSelection() {
        var state = PhotoSlideshow()
        state.setPlaying(true); XCTAssertFalse(state.playing); XCTAssertNil(state.selectedIndex)
        state.updateCount(5); state.select(4); state.setPlaying(true)
        state.updateCount(2); XCTAssertEqual(state.selectedIndex, 1)
        state.updateCount(0); XCTAssertNil(state.selectedIndex); XCTAssertFalse(state.playing)
    }
    func testSlideshowWrapsBothDirectionsAndSelectsBeforePlaying() {
        var state = PhotoSlideshow(); state.updateCount(3); state.setPlaying(true)
        XCTAssertEqual(state.selectedIndex, 0)
        state.move(-1); XCTAssertEqual(state.selectedIndex, 2)
        state.move(1); XCTAssertEqual(state.selectedIndex, 0)
        state.select(99); XCTAssertEqual(state.selectedIndex, 2)
        state.select(-20); XCTAssertEqual(state.selectedIndex, 0)
    }
    func testNextAndPreviousChooseAnEndpointWithoutExistingSelection() {
        var first = PhotoSlideshow(); first.updateCount(4); first.move(1)
        XCTAssertEqual(first.selectedIndex, 0)
        var last = PhotoSlideshow(); last.updateCount(4); last.move(-1)
        XCTAssertEqual(last.selectedIndex, 3)
    }
}
