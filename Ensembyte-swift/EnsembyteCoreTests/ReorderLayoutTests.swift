import XCTest
@testable import Ensembyte

final class ReorderLayoutTests: XCTestCase {
    // One scenario pins the behavior of one branch of `reorder`: an expected
    // result worked out by hand from ChatView's original inline algorithm, so
    // the extraction stays a behavior-identity, not a re-implementation.
    private struct Scenario {
        let name: String
        let moving: Int
        let target: Int
        let capacity: Int
        let others: [Int: ReorderLayout.PanelPlace]
        let previous: ReorderLayout.PanelPlace?
        let expectedN: Int
        let expectedPlacements: [Int: ReorderLayout.PanelPlace]
        let expectedOrder: [Int]
    }

    private func place(isTop: Bool, below: Int) -> ReorderLayout.PanelPlace {
        ReorderLayout.PanelPlace(isTop: isTop, below: below)
    }

    private var scenarios: [Scenario] { [
        // (a) Empty side: the moving panel lands alone in the target slot; with
        // two slots the bottom slot maps to (isTop: false, below: 0).
        Scenario(
            name: "emptySide",
            moving: 7, target: 1, capacity: 2,
            others: [:], previous: nil,
            expectedN: 2,
            expectedPlacements: [7: place(isTop: false, below: 0)],
            expectedOrder: [7]
        ),
        // (b) Single panel: the new panel takes the free top slot; no
        // displacement, no split beyond the top half.
        Scenario(
            name: "singlePanel",
            moving: 2, target: 1, capacity: 3,
            others: [1: place(isTop: true, below: 0)], previous: nil,
            expectedN: 3,
            expectedPlacements: [1: place(isTop: true, below: 0), 2: place(isTop: true, below: 1)],
            expectedOrder: [1, 2]
        ),
        // (c) Top-half move: the panel moves from slot 1 to slot 0 on a not-full
        // side; the backward direction walks off the grid and the displaced
        // panel is placed in the lowest free slot.
        Scenario(
            name: "topHalfMove",
            moving: 2, target: 0, capacity: 3,
            others: [1: place(isTop: true, below: 0), 3: place(isTop: true, below: 1), 4: place(isTop: false, below: 0)],
            previous: place(isTop: true, below: 1),
            expectedN: 4,
            expectedPlacements: [
                2: place(isTop: true, below: 0),
                3: place(isTop: true, below: 1),
                1: place(isTop: false, below: 1),
                4: place(isTop: false, below: 0)
            ],
            expectedOrder: [2, 3, 4, 1]
        ),
        // (d) Bottom-half move: bottom places map through `n - 1 - below` both
        // ways — the incoming panel's old bottom slot becomes its swap partner,
        // and the occupant that climbs into the top half re-maps too.
        Scenario(
            name: "bottomHalfMove",
            moving: 7, target: 2, capacity: 3,
            others: [5: place(isTop: false, below: 0)],
            previous: place(isTop: false, below: 1),
            expectedN: 3,
            expectedPlacements: [5: place(isTop: true, below: 1), 7: place(isTop: false, below: 0)],
            expectedOrder: [5, 7]
        ),
        // (e) Full swap: a full side and a taken target swap the target for the
        // moving panel's old slot; nothing is displaced, only exchanged.
        Scenario(
            name: "fullSwap",
            moving: 4, target: 0, capacity: 4,
            others: [1: place(isTop: true, below: 0), 2: place(isTop: true, below: 1), 3: place(isTop: false, below: 0)],
            previous: place(isTop: false, below: 1),
            expectedN: 4,
            expectedPlacements: [
                4: place(isTop: true, below: 0),
                2: place(isTop: true, below: 1),
                1: place(isTop: false, below: 1),
                3: place(isTop: false, below: 0)
            ],
            expectedOrder: [4, 2, 3, 1]
        ),
        // (f) `others` ordering assembly: the side's order is the top half in
        // index order, then the bottom half reversed (deepest first).
        Scenario(
            name: "orderAssembly",
            moving: 9, target: 2, capacity: 3,
            others: [1: place(isTop: true, below: 0), 2: place(isTop: true, below: 1), 3: place(isTop: false, below: 0)],
            previous: nil,
            expectedN: 4,
            expectedPlacements: [
                1: place(isTop: true, below: 0),
                2: place(isTop: true, below: 1),
                9: place(isTop: false, below: 1),
                3: place(isTop: false, below: 0)
            ],
            expectedOrder: [1, 2, 3, 9]
        )
    ] }

    func testReorder() {
        for scenario in scenarios {
            let result = ReorderLayout.reorder(
                moving: scenario.moving,
                to: scenario.target,
                capacity: scenario.capacity,
                others: scenario.others,
                previous: scenario.previous
            )
            XCTAssertEqual(result.n, scenario.expectedN, scenario.name)
            XCTAssertEqual(result.placements, scenario.expectedPlacements, scenario.name)
            XCTAssertEqual(result.order, scenario.expectedOrder, scenario.name)
        }
    }
}
