import Foundation

/// Index-only state; no image arrays are retained by the slideshow.
struct PhotoSlideshow {
    private(set) var count = 0
    private(set) var selectedIndex: Int?
    private(set) var playing = false
    var interval: TimeInterval = 5

    mutating func updateCount(_ count: Int) {
        self.count = max(0, count)
        if self.count == 0 { selectedIndex = nil; playing = false }
        else if let selectedIndex { self.selectedIndex = min(selectedIndex, self.count - 1) }
    }
    mutating func select(_ index: Int) {
        guard count > 0 else { selectedIndex = nil; return }
        selectedIndex = min(max(0, index), count - 1)
    }
    mutating func move(_ offset: Int) {
        guard count > 0 else { return }
        guard let selectedIndex else { self.selectedIndex = offset < 0 ? count - 1 : 0; return }
        let next = (selectedIndex + offset) % count
        selectedIndex = next >= 0 ? next : next + count
    }
    mutating func setPlaying(_ playing: Bool) {
        self.playing = playing && count > 0
        if self.playing && selectedIndex == nil { selectedIndex = 0 }
    }
}
