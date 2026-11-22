import Foundation
import Testing
@testable import ClipdeckCore

@Suite("HistoryModel")
@MainActor
struct HistoryModelTests {
    private func makeModel(_ texts: [String] = ["a", "b", "c"]) throws -> (HistoryModel, HistoryStore) {
        let clock = TestClock()
        let store = try makeStore(clock: clock)
        for text in texts {
            clock.advance(by: 1)
            try store.record(textCandidate(text))
        }
        let model = HistoryModel(store: store)
        model.reload()
        return (model, store)
    }

    @Test("should load the newest items first and select the first one")
    func load() throws {
        let (model, _) = try makeModel()
        #expect(model.items.map(\.text) == ["c", "b", "a"])
        #expect(model.selectedItem?.text == "c")
        #expect(model.totalCount == 3)
        #expect(model.errorMessage == nil)
    }

    @Test("should reload when the search or filter changes")
    func reloadOnChange() throws {
        let (model, store) = try makeModel()
        try store.record(ClipCandidate(kind: .link, text: "https://x.com"))
        model.search = "b"
        #expect(model.items.map(\.text) == ["b"])
        #expect(model.selectedItem?.text == "b")
        model.search = ""
        model.filter = .links
        #expect(model.items.map(\.text) == ["https://x.com"])
    }

    @Test("should move the selection and stop at both ends")
    func moveSelection() throws {
        let (model, _) = try makeModel()
        model.moveSelection(by: 1)
        #expect(model.selectedItem?.text == "b")
        model.moveSelection(by: 5)
        #expect(model.selectedItem?.text == "a")
        model.moveSelection(by: -9)
        #expect(model.selectedItem?.text == "c")
    }

    @Test("should do nothing when moving the selection in an empty list")
    func moveEmpty() throws {
        let (model, _) = try makeModel([])
        model.moveSelection(by: 1)
        #expect(model.selectedID == nil)
    }

    @Test("should cycle through filters in both directions and wrap around")
    func cycleFilter() throws {
        let (model, _) = try makeModel()
        model.cycleFilter(by: 1)
        #expect(model.filter == .text)
        model.cycleFilter(by: -2)
        #expect(model.filter == .pinned)
    }

    @Test("should clear the search and select the newest item when shown again")
    func prepareForShow() throws {
        let (model, store) = try makeModel()
        model.search = "a"
        try store.record(textCandidate("newest"))
        model.prepareForShow()
        #expect(model.search.isEmpty)
        #expect(model.selectedItem?.text == "newest")
        #expect(model.showCount == 1)
    }

    @Test("should select the next item after deleting the selected one")
    func deleteSelected() throws {
        let (model, _) = try makeModel()
        model.moveSelection(by: 1)
        model.delete(try #require(model.selectedItem))
        #expect(model.items.map(\.text) == ["c", "a"])
        #expect(model.selectedItem?.text == "a")
        model.delete(try #require(model.selectedItem))
        #expect(model.selectedItem?.text == "c")
    }

    @Test("should pin and unpin an item")
    func pin() throws {
        let (model, _) = try makeModel()
        model.togglePin(try #require(model.item(at: 1)))
        #expect(model.item(at: 1)?.isPinned == true)
        model.togglePin(try #require(model.item(at: 1)))
        #expect(model.item(at: 1)?.isPinned == false)
        #expect(model.item(at: 99) == nil)
    }

    @Test("should clear everything except pinned items")
    func clear() throws {
        let (model, _) = try makeModel()
        model.togglePin(try #require(model.item(at: 2)))
        model.clearUnpinned()
        #expect(model.items.map(\.text) == ["a"])
        #expect(model.imageURL(for: try #require(model.item(at: 0))) == nil)
    }
}
