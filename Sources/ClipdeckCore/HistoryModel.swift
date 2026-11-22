import Foundation
import Observation

@Observable
@MainActor
public final class HistoryModel {
    public private(set) var items: [ClipItem] = []
    public private(set) var totalCount = 0
    public private(set) var errorMessage: String?
    public private(set) var showCount = 0
    public var selectedID: Int64?

    public var filter: HistoryFilter = .all {
        didSet { if filter != oldValue { reload() } }
    }

    public var search = "" {
        didSet { if search != oldValue { reload() } }
    }

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let limit: Int

    public init(store: HistoryStore, limit: Int = 1_000) {
        self.store = store
        self.limit = limit
    }

    public var selectedItem: ClipItem? {
        items.first { $0.id == selectedID }
    }

    public func item(at index: Int) -> ClipItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    public func imageURL(for item: ClipItem) -> URL? {
        store.imageURL(for: item)
    }

    public func reload() {
        do {
            items = try store.previews(matching: HistoryQuery(filter: filter, search: search), limit: limit)
            totalCount = try store.count()
            errorMessage = nil
        } catch {
            errorMessage = "Your history could not be loaded. \(error)"
        }
        if selectedItem == nil {
            selectedID = items.first?.id
        }
    }

    public func prepareForShow() {
        search = ""
        reload()
        selectedID = items.first?.id
        showCount += 1
    }

    public func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[min(max(current + offset, 0), items.count - 1)].id
    }

    public func cycleFilter(by offset: Int) {
        let filters = HistoryFilter.allCases
        let index = filters.firstIndex(of: filter) ?? 0
        filter = filters[(index + offset % filters.count + filters.count) % filters.count]
    }

    public func togglePin(_ item: ClipItem) {
        perform { try store.setPinned(!item.isPinned, id: item.id) }
    }

    public func delete(_ doomed: ClipItem) {
        let index = items.firstIndex { $0.id == doomed.id } ?? 0
        perform { try store.delete(id: doomed.id) }
        selectedID = item(at: min(index, items.count - 1))?.id
    }

    public func clearUnpinned() {
        perform { try store.clearUnpinned() }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = "That change could not be saved. \(error)"
        }
        reload()
    }
}
