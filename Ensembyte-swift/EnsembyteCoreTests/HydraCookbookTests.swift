import XCTest
@testable import Ensembyte

final class HydraCookbookTests: XCTestCase {
    private func option(id: String = "model", efforts: [String]) -> ModelOption {
        ModelOption(id: id, name: id, efforts: efforts)
    }

    // MARK: - effort(_:for:)

    func testEffortKeptWhenOffered() {
        let offers = option(efforts: ["low", "medium", "high"])
        XCTAssertEqual(HydraCookbook.effort("high", for: offers), "high")
        XCTAssertEqual(HydraCookbook.effort("medium", for: offers), "medium")
    }

    func testEffortNilWhenUnoffered() {
        let offers = option(efforts: ["medium"])
        XCTAssertEqual(HydraCookbook.effort("high", for: offers), nil)
        XCTAssertEqual(HydraCookbook.effort("max", for: offers), nil)
    }

    func testEffortNilInputs() {
        XCTAssertNil(HydraCookbook.effort(nil, for: option(efforts: ["high"])))
        XCTAssertNil(HydraCookbook.effort("high", for: nil))
        XCTAssertNil(HydraCookbook.effort(nil, for: nil))
    }

    // MARK: - Recipe book

    func testRecipesAreWellFormed() {
        let ids = HydraCookbook.recipes.map(\.id)
        XCTAssertEqual(ids.count, HydraCookbook.recipes.count)
        XCTAssertEqual(Set(ids).count, ids.count, "recipe ids must be unique")

        for recipe in HydraCookbook.recipes {
            XCTAssertFalse(recipe.title.isEmpty, "\(recipe.id) needs a title")
            XCTAssertFalse(recipe.tagline.isEmpty, "\(recipe.id) needs a tagline")
            XCTAssertFalse(recipe.lead.models.isEmpty, "\(recipe.id) must name lead models")
            XCTAssertFalse(recipe.lead.providers.isEmpty, "\(recipe.id) must name lead providers")
            XCTAssertFalse(recipe.heads.models.isEmpty, "\(recipe.id) must name head models")
            XCTAssertFalse(recipe.heads.providers.isEmpty, "\(recipe.id) must name head providers")
            if let maxHeads = recipe.maxHeads {
                XCTAssertTrue(maxHeads > 0, "\(recipe.id) with a cap must cap at least one head")
            }
        }
    }

    // MARK: - isAdded(_:in:)

    private func pair(_ provider: ProviderKind, lead: String?, _ workerProvider: ProviderKind? = nil, worker: String?) -> HydraPair {
        var pair = HydraPair(provider: provider)
        pair.orchestratorModel = lead
        pair.workerProvider = workerProvider
        pair.workerModel = worker
        return pair
    }

    func testIsAdded() {
        let mine = pair(.claude, lead: "Fable", worker: "Opus")
        let same = pair(.claude, lead: "Fable", worker: "Opus")
        let other = pair(.claude, lead: "Fable", worker: "Terra")
        let otherProvider = pair(.codex, lead: "Fable", worker: "Opus")
        let empty: [HydraPair] = []

        XCTAssertTrue(HydraCookbook.isAdded(mine, in: [mine]))
        XCTAssertTrue(HydraCookbook.isAdded(mine, in: [mine, same, other]))
        XCTAssertTrue(HydraCookbook.isAdded(mine, in: [same]))
        XCTAssertFalse(HydraCookbook.isAdded(mine, in: empty))
        XCTAssertFalse(HydraCookbook.isAdded(mine, in: [otherProvider]))
        XCTAssertFalse(HydraCookbook.isAdded(mine, in: [other]))
    }

    func testIsAddedIgnoresOptionalFields() {
        let base = pair(.claude, lead: "Fable", worker: "Opus")
        var withEffort = base
        withEffort.orchestratorEffort = "high"
        var named = base
        named.name = "My pair"
        // `isAdded` compares providers and models only, not effort, name or speed.
        XCTAssertTrue(HydraCookbook.isAdded(base, in: [withEffort]))
        XCTAssertTrue(HydraCookbook.isAdded(base, in: [named]))
    }
}
