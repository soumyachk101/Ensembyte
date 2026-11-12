import SwiftUI

/// The app-wide zoom: the window's content is laid out in the space the window has divided
/// by the scale, then drawn back up, so a bigger zoom shows less at once instead of clipping.
enum AppZoom {
    static let levels = [75, 90, 100, 110, 125, 150, 175, 200]

    static func normalized(_ percent: Int) -> Int {
        levels.contains(percent) ? percent : 100
    }

    static func next(_ percent: Int, increasing: Bool) -> Int {
        let current = normalized(percent)
        return increasing ? (levels.first { $0 > current } ?? current) : (levels.last { $0 < current } ?? current)
    }
}
