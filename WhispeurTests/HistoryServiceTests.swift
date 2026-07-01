// HistoryServiceTests.swift
// WhispeurTests

import Testing

@MainActor
struct HistoryServiceTests {

    @Test("Adding an item stores it at the front")
    func addItemInsertsAtFront() {
        let service = HistoryService()
        service.clearAll()

        service.add("first")
        service.add("second")

        #expect(service.items.first?.text == "second")
        #expect(service.items.count == 2)
    }

    @Test("Blank text is not added")
    func blankTextIgnored() {
        let service = HistoryService()
        service.clearAll()

        service.add("   ")
        service.add("")

        #expect(service.items.isEmpty)
    }

    @Test("clearAll empties the list")
    func clearAllEmptiesList() {
        let service = HistoryService()
        service.add("something")
        service.clearAll()
        #expect(service.items.isEmpty)
    }

    @Test("List is capped at 100 items")
    func listCappedAt100() {
        let service = HistoryService()
        service.clearAll()

        for i in 1...110 {
            service.add("item \(i)")
        }

        #expect(service.items.count == 100)
        // Most-recent item should be "item 110"
        #expect(service.items.first?.text == "item 110")
    }
}
