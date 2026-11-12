/// The pure layout math of one side's panel stack when a held panel takes the
/// slot it is over: a free slot is taken, a taken one on a full side is
/// swapped for the panel's old slot, otherwise the occupant and the rest move
/// one slot along. Plain values in and out, so ChatView's reorder calls it
/// and the Core tests drive it.
enum ReorderLayout {
    /// Where a panel sits in a side's stack: its half (the top counts down
    /// from the chrome row, the bottom counts up from the chat box) and its
    /// depth within that half.
    struct PanelPlace: Hashable {
        var isTop: Bool
        var below: Int
    }

    /// The side's stack after the reorder.
    struct Result<ID: Hashable> {
        /// The side's slot count: its capacity and what it already holds,
        /// whichever is the greater.
        var n: Int
        /// Where each panel on the side lands.
        var placements: [ID: PanelPlace]
        /// The side's order: the top half in index order, the bottom half
        /// reversed.
        var order: [ID]
    }

    /// `others` are the panels on the side, the moving one aside, with their
    /// current places; `previous` is the moving panel's place, nil when it
    /// comes in from the other side; `target` is the slot the pointer is
    /// over, in a grid of `capacity` slots the pane gives the side.
    static func reorder<ID: Hashable>(
        moving id: ID,
        to target: Int,
        capacity: Int,
        others: [ID: PanelPlace],
        previous: PanelPlace?
    ) -> Result<ID> {
        let n = max(capacity, others.count + 1)
        // A panel in a top corner with `below = b` sits in slot `b`, one in a
        // bottom corner in slot `n - 1 - b`.
        var occupancy: [Int: ID] = [:]
        for (panelID, place) in others {
            occupancy[place.isTop ? place.below : n - 1 - place.below] = panelID
        }
        let previousIndex = previous.map { $0.isTop ? $0.below : n - 1 - $0.below }
        // A full side holds exactly what the pane gives it: a taken target
        // swaps with the moving panel's old slot there.
        let full = !(others.count + 1 > capacity)
        if let other = occupancy[target], previousIndex != nil, full {
            occupancy[previousIndex!] = other
            occupancy[target] = id
        } else if let other = occupancy[target] {
            occupancy.removeValue(forKey: target)
            occupancy[target] = id
            let forward = previousIndex == nil || previousIndex! < target
            var displaced = other
            var next = target + (forward ? 1 : -1)
            while true {
                if next < 0 || next >= n {
                    let free = forward ? (0..<n).first(where: { occupancy[$0] == nil }) : (0..<n).reversed().first(where: { occupancy[$0] == nil })
                    if let free { occupancy[free] = displaced }
                    break
                }
                if occupancy[next] == nil {
                    occupancy[next] = displaced
                    break
                }
                let occupant = occupancy[next]!
                occupancy[next] = displaced
                displaced = occupant
                next += forward ? 1 : -1
            }
        } else {
            occupancy[target] = id
        }
        let half = (n - 1) / 2
        var placements: [ID: PanelPlace] = [:]
        for (index, panelID) in occupancy {
            let isTop = index <= half
            placements[panelID] = PanelPlace(isTop: isTop, below: isTop ? index : n - 1 - index)
        }
        let byIndex = occupancy.sorted { $0.key < $1.key }
        let top = byIndex.filter { $0.key <= half }.map(\.value)
        let bottom = byIndex.filter { $0.key > half }.map(\.value).reversed()
        return Result(n: n, placements: placements, order: top + bottom)
    }
}
