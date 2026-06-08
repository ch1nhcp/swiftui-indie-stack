//
//  StreakViewModel.swift
//  MyApp
//
//  Provides streak data to the UI.
//
//  Two modes based on AppConfiguration.useFirebase:
//
//  Firebase Mode (useFirebase = true):
//  - All streak logic runs on the backend (Firebase Functions)
//  - This class simply displays data from Firestore
//  - Backend calculates streaks, sends reminders, applies freezes
//
//  Local Mode (useFirebase = false):
//  - Simple local streak tracking using UserDefaults
//  - Basic streak calculation (daily activity)
//  - No freezes, no reminders, no cloud sync
//

import Foundation
import SwiftUI
import WidgetKit

#if canImport(Firebase)
import FirebaseFirestore
#endif

// MARK: - Type Alias for Backward Compatibility
// Existing code uses StreakDataProvider.shared - this maintains compatibility
typealias StreakDataProvider = StreakViewModel

/// Provides streak data to SwiftUI views
@Observable
class StreakViewModel {

    // MARK: - Singleton

    static let shared = StreakViewModel()

    // MARK: - State

    var streakData: StreakData = .empty
    var isLoading: Bool = false

    // MARK: - Dependencies

    #if canImport(Firebase)
    @ObservationIgnored
    private var listener: ListenerRegistration?
    @ObservationIgnored
    private var db: Firestore?
    #endif

    // Local storage keys
    @ObservationIgnored
    private let currentStreakKey = "localCurrentStreak"
    @ObservationIgnored
    private let bestStreakKey = "localBestStreak"
    @ObservationIgnored
    private let lastActivityKey = "localLastActivityDate"
    @ObservationIgnored
    private let streakStartKey = "localStreakStartDate"
    @ObservationIgnored
    private let activeDaysKey = "localActiveDays"

    // MARK: - Initialization

    private init() {
        #if canImport(Firebase)
        if AppConfiguration.useFirebase {
            db = Firestore.firestore()
        }
        #endif

        loadLocalData()
    }

    // MARK: - Firebase Listener (Cloud Mode)

    /// Start listening to streak updates from Firestore
    func startListening(userId: String) {
        guard AppConfiguration.useFirebase else {
            loadLocalData()
            return
        }

        #if canImport(Firebase)
        stopListening()

        guard let db = db else { return }

        isLoading = true

        listener = db.collection("users").document(userId)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }

                self.isLoading = false

                if let error = error {
                    debugPrint("Error listening to streak updates: \(error)")
                    return
                }

                guard let data = documentSnapshot?.data(),
                      let streakDict = data["streak"] as? [String: Any] else {
                    return
                }

                self.updateFromFirestore(streakDict)
            }
        #endif
    }

    /// Stop listening to Firestore updates
    func stopListening() {
        #if canImport(Firebase)
        listener?.remove()
        listener = nil
        #endif
    }

    /// Update local streak data from Firestore dictionary
    func updateFromFirestore(_ data: [String: Any]) {
        let currentStreak = data["currentStreak"] as? Int ?? 0
        let bestStreak = data["bestStreak"] as? Int ?? 0
        let isAtRisk = data["isAtRisk"] as? Bool ?? false
        let freezesAvailable = data["freezesAvailable"] as? Int ?? 0
        let freezeActive = data["freezeActive"] as? Bool ?? false

        var lastActivityDate: Date?
        var streakStartDate: Date?
        var activeDays: [Date] = []

        #if canImport(Firebase)
        if let timestamp = data["lastActivityDate"] as? Timestamp {
            lastActivityDate = timestamp.dateValue()
        }

        if let timestamp = data["streakStartDate"] as? Timestamp {
            streakStartDate = timestamp.dateValue()
        }

        if let timestamps = data["activeDays"] as? [Timestamp] {
            activeDays = timestamps.map { $0.dateValue() }
        }
        #endif

        DispatchQueue.main.async {
            self.streakData = StreakData(
                currentStreak: currentStreak,
                bestStreak: bestStreak,
                lastActivityDate: lastActivityDate,
                streakStartDate: streakStartDate,
                isAtRisk: isAtRisk,
                freezesAvailable: freezesAvailable,
                freezeActive: freezeActive,
                activeDays: activeDays
            )

            WidgetHelper.updateWidget(with: self.streakData)

            AppReviewManager.shared.requestReviewIfAppropriate(for: currentStreak)
        }
    }

    // MARK: - Local Mode

    /// Load streak data from UserDefaults (local mode)
    private func loadLocalData() {
        let defaults = UserDefaults.standard

        let currentStreak = defaults.integer(forKey: currentStreakKey)
        let bestStreak = defaults.integer(forKey: bestStreakKey)

        var lastActivityDate: Date?
        if let timestamp = defaults.object(forKey: lastActivityKey) as? TimeInterval {
            lastActivityDate = Date(timeIntervalSince1970: timestamp)
        }

        var streakStartDate: Date?
        if let timestamp = defaults.object(forKey: streakStartKey) as? TimeInterval {
            streakStartDate = Date(timeIntervalSince1970: timestamp)
        }

        var activeDays: [Date] = []
        if let timestamps = defaults.array(forKey: activeDaysKey) as? [TimeInterval] {
            activeDays = timestamps.map { Date(timeIntervalSince1970: $0) }
        }

        var isAtRisk = false
        if let last = lastActivityDate {
            let calendar = Calendar.current
            let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
            isAtRisk = !calendar.isDate(last, inSameDayAs: Date()) &&
                       !calendar.isDate(last, inSameDayAs: yesterday)
        }

        self.streakData = StreakData(
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastActivityDate: lastActivityDate,
            streakStartDate: streakStartDate,
            isAtRisk: isAtRisk,
            freezesAvailable: 0,
            freezeActive: false,
            activeDays: activeDays
        )

        WidgetHelper.updateWidget(with: self.streakData)
    }

    /// Save streak data to UserDefaults (local mode)
    private func saveLocalData() {
        let defaults = UserDefaults.standard

        defaults.set(streakData.currentStreak, forKey: currentStreakKey)
        defaults.set(streakData.bestStreak, forKey: bestStreakKey)

        if let date = streakData.lastActivityDate {
            defaults.set(date.timeIntervalSince1970, forKey: lastActivityKey)
        }

        if let date = streakData.streakStartDate {
            defaults.set(date.timeIntervalSince1970, forKey: streakStartKey)
        }

        let timestamps = streakData.activeDays.map { $0.timeIntervalSince1970 }
        defaults.set(timestamps, forKey: activeDaysKey)
    }

    /// Record activity locally (for local mode only)
    func recordLocalActivity() {
        guard !AppConfiguration.useFirebase else {
            return
        }

        let updated = StreakData.calculateUpdatedStreak(from: streakData)

        guard updated.currentStreak != streakData.currentStreak ||
              updated.lastActivityDate != streakData.lastActivityDate else {
            return
        }

        DispatchQueue.main.async {
            self.streakData = updated
            self.saveLocalData()

            WidgetHelper.updateWidget(with: self.streakData)

            AppReviewManager.shared.requestReviewIfAppropriate(for: updated.currentStreak)
        }
    }

    // MARK: - Computed Properties

    var hasStreak: Bool {
        streakData.currentStreak > 0
    }

    var isMilestone: Bool {
        streakData.isMilestone
    }

    var streakText: String {
        if streakData.currentStreak == 1 {
            return "1 day"
        } else {
            return "\(streakData.currentStreak) days"
        }
    }

    var isEnabled: Bool {
        AppConfiguration.enableStreaks
    }
}
