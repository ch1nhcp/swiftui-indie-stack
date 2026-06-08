//
//  LibraryViewModelTests.swift
//  MyAppTests
//
//  Tests for library filtering, date logic, and data source injection.
//

import Testing
import Foundation
@testable import MyApp

// MARK: - Mock Data Source

struct MockLibraryDataSource: LibraryDataSource {
    var indexData: Data = Data()
    var contentData: Data = Data()
    var shouldFail = false

    func fetchData(from url: URL) async throws -> Data {
        if shouldFail {
            throw URLError(.notConnectedToInternet)
        }
        if url.absoluteString.hasSuffix(".json") {
            return indexData
        }
        return contentData
    }
}

// MARK: - Test Helpers

private let calendar = Calendar.current

private func makeDate(daysFromNow offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: Date())!
}

private func sampleEntry(
    id: String = "test",
    title: String = "Test Article",
    summary: String = "A test article",
    category: String = "tips",
    publishDate: Date = makeDate(daysFromNow: -1),
    expiryDate: Date? = nil,
    featured: Bool? = nil
) -> LibraryEntry {
    LibraryEntry(
        id: id, title: title, summary: summary,
        contentURL: "https://example.com/\(id).md",
        publishDate: publishDate, expiryDate: expiryDate,
        category: category, imageURL: nil, featured: featured,
        version: "1.0"
    )
}

private func sampleIndex(articles: [LibraryEntry]) -> LibraryIndex {
    LibraryIndex(lastUpdated: Date(), articles: articles, version: "1.0")
}

// MARK: - Filtering Tests

@Suite("Library Filtering")
struct LibraryFilteringTests {

    @Test("Filter by category returns only matching entries")
    func filterByCategory() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", category: "tips"),
            sampleEntry(id: "2", category: "features"),
            sampleEntry(id: "3", category: "tips"),
        ])
        vm.processEntries(from: index)
        vm.selectedCategory = "tips"

        #expect(vm.filteredEntries.count == 2)
        #expect(vm.filteredEntries.allSatisfy { $0.category == "tips" })
    }

    @Test("Nil category returns all entries")
    func noFilter() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", category: "tips"),
            sampleEntry(id: "2", category: "features"),
        ])
        vm.processEntries(from: index)
        vm.selectedCategory = nil

        #expect(vm.filteredEntries.count == 2)
    }

    @Test("Search filters by title")
    func searchByTitle() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", title: "Getting Started Guide"),
            sampleEntry(id: "2", title: "Advanced Tips"),
        ])
        vm.processEntries(from: index)
        vm.searchText = "started"

        #expect(vm.filteredEntries.count == 1)
        #expect(vm.filteredEntries.first?.id == "1")
    }

    @Test("Search filters by summary")
    func searchBySummary() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", title: "Article", summary: "Learn about streaks"),
            sampleEntry(id: "2", title: "Article", summary: "Learn about settings"),
        ])
        vm.processEntries(from: index)
        vm.searchText = "streaks"

        #expect(vm.filteredEntries.count == 1)
        #expect(vm.filteredEntries.first?.id == "1")
    }

    @Test("Multi-word search requires all terms to match")
    func multiWordSearch() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", title: "Getting Started Guide", summary: "A quick guide"),
            sampleEntry(id: "2", title: "Getting Better", summary: "Improvement tips"),
        ])
        vm.processEntries(from: index)
        vm.searchText = "getting guide"

        #expect(vm.filteredEntries.count == 1)
        #expect(vm.filteredEntries.first?.id == "1")
    }

    @Test("Available categories derived from entries")
    func availableCategories() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "1", category: "tips"),
            sampleEntry(id: "2", category: "features"),
            sampleEntry(id: "3", category: "tips"),
        ])
        vm.processEntries(from: index)

        #expect(vm.availableCategories.count == 2)
        #expect(vm.availableCategories.contains("tips"))
        #expect(vm.availableCategories.contains("features"))
    }
}

// MARK: - Date Filtering Tests

@Suite("Library Date Filtering")
struct LibraryDateFilteringTests {

    @Test("Future publish dates are excluded")
    func futureExcluded() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "published", publishDate: makeDate(daysFromNow: -1)),
            sampleEntry(id: "future", publishDate: makeDate(daysFromNow: 5)),
        ])
        vm.processEntries(from: index)

        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.id == "published")
    }

    @Test("Expired entries are excluded")
    func expiredExcluded() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "active", publishDate: makeDate(daysFromNow: -10)),
            sampleEntry(id: "expired", publishDate: makeDate(daysFromNow: -10), expiryDate: makeDate(daysFromNow: -1)),
        ])
        vm.processEntries(from: index)

        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.id == "active")
    }

    @Test("Entries sorted newest first")
    func sortedByDate() {
        let vm = LibraryViewModel()
        let index = sampleIndex(articles: [
            sampleEntry(id: "older", publishDate: makeDate(daysFromNow: -10)),
            sampleEntry(id: "newer", publishDate: makeDate(daysFromNow: -1)),
        ])
        vm.processEntries(from: index)

        #expect(vm.entries.first?.id == "newer")
        #expect(vm.entries.last?.id == "older")
    }
}

// MARK: - Entry New Check

@Suite("Library Entry Recency")
struct LibraryEntryRecencyTests {

    @Test("Entry published within 30 days is new")
    func recentEntryIsNew() {
        let vm = LibraryViewModel()
        let recent = makeDate(daysFromNow: -5)
        #expect(vm.isEntryNew(recent))
    }

    @Test("Entry published over 30 days ago is not new")
    func oldEntryIsNotNew() {
        let vm = LibraryViewModel()
        let old = makeDate(daysFromNow: -45)
        #expect(!vm.isEntryNew(old))
    }
}

// MARK: - Data Source Injection Tests

@Suite("Library Data Source")
struct LibraryDataSourceTests {

    @Test("ViewModel uses injected data source for fetching")
    @MainActor
    func injectedDataSource() async {
        let article = sampleEntry(id: "injected", title: "From Mock")
        let index = sampleIndex(articles: [article])
        let data = try! JSONEncoder.libraryEncoder.encode(index)

        let mock = MockLibraryDataSource(indexData: data)
        let vm = LibraryViewModel(dataSource: mock)

        await vm.fetchEntries()

        #expect(vm.entries.count == 1)
        #expect(vm.entries.first?.title == "From Mock")
        #expect(vm.errorMessage == nil)
    }

    @Test("ViewModel surfaces error from failing data source")
    @MainActor
    func failingDataSource() async {
        let mock = MockLibraryDataSource(shouldFail: true)
        let vm = LibraryViewModel(dataSource: mock)

        await vm.fetchEntries(forceRefresh: true)

        #expect(vm.entries.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}
