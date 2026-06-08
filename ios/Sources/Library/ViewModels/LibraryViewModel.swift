//
//  LibraryViewModel.swift
//  MyApp
//
//  ViewModel for fetching and filtering library content.
//

import Foundation
import SwiftUI

// MARK: - Data Source Protocol

protocol LibraryDataSource: Sendable {
    func fetchData(from url: URL) async throws -> Data
}

struct URLSessionDataSource: LibraryDataSource {
    func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

// MARK: - ViewModel

@Observable
class LibraryViewModel {

    var entries: [LibraryEntry] = []
    var selectedCategory: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var lastUpdated: Date?
    var searchText: String = ""

    var filteredEntries: [LibraryEntry] {
        var filtered = entries

        if let category = selectedCategory {
            filtered = filtered.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let searchTerms = searchText.lowercased().split(separator: " ").map(String.init)
            filtered = filtered.filter { entry in
                let title = entry.title.lowercased()
                let summary = entry.summary.lowercased()
                return searchTerms.allSatisfy { term in
                    title.contains(term) || summary.contains(term)
                }
            }
        }

        return filtered
    }

    var availableCategories: [String] {
        Set(entries.map { $0.category }).sorted {
            formatCategoryName($0) < formatCategoryName($1)
        }
    }

    var hasFeaturedEntries: Bool {
        filteredEntries.contains { $0.featured == true }
    }

    private let cacheManager = LibraryCacheManager.shared
    private let dataSource: LibraryDataSource
    private let indexURL = AppConfiguration.libraryIndexURL

    init(dataSource: LibraryDataSource = URLSessionDataSource()) {
        self.dataSource = dataSource
    }

    // MARK: - Fetching

    @MainActor
    func fetchEntries(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil

        if !forceRefresh,
           let cachedIndex = cacheManager.getCachedIndex(),
           let cachedDate = cacheManager.getIndexLastUpdated(),
           Calendar.current.isDateInToday(cachedDate) {

            processEntries(from: cachedIndex)
            lastUpdated = cachedDate
            isLoading = false
            return
        }

        guard let url = URL(string: indexURL) else {
            errorMessage = "Invalid index URL"
            isLoading = false
            return
        }

        do {
            let data = try await dataSource.fetchData(from: url)
            let libraryIndex = try JSONDecoder.libraryDecoder.decode(LibraryIndex.self, from: data)
            cacheManager.cacheIndex(libraryIndex)
            processEntries(from: libraryIndex)
            lastUpdated = libraryIndex.lastUpdated
        } catch {
            errorMessage = "Failed to fetch library: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func processEntries(from index: LibraryIndex) {
        let now = Date()
        entries = index.articles
            .filter { article in
                let isPublished = article.publishDate <= now
                let isNotExpired = article.expiryDate == nil || article.expiryDate! >= now
                return isPublished && isNotExpired
            }
            .sorted(by: { $0.publishDate > $1.publishDate })
    }

    // MARK: - Content Fetching

    func fetchEntryContent(for entry: LibraryEntry) async throws -> String {
        let versionHash = entry.version.hashValue

        if let cachedContent = cacheManager.getCachedContent(for: entry.id, version: versionHash) {
            return cachedContent
        }

        guard let url = URL(string: entry.contentURL) else {
            throw URLError(.badURL)
        }

        let data = try await dataSource.fetchData(from: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        cacheManager.cacheContent(content, for: entry.id, version: versionHash)
        return content
    }

    // MARK: - Helpers

    func resetCategory() {
        selectedCategory = nil
    }

    func displayNameForCategory(_ category: String) -> String {
        formatCategoryName(category)
    }

    func isEntryNew(_ publishDate: Date) -> Bool {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return publishDate > thirtyDaysAgo
    }
}
