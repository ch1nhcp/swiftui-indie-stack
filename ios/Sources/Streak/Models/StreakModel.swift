//
//  StreakModel.swift
//  MyApp
//
//  Data structures for the streak system.
//

import Foundation

/// Streak data model
struct StreakData: Codable {
    let currentStreak: Int
    let bestStreak: Int
    let lastActivityDate: Date?
    let streakStartDate: Date?
    let isAtRisk: Bool
    let freezesAvailable: Int
    let freezeActive: Bool
    let activeDays: [Date]  // Days with activity in current month (for calendar)

    static var empty: StreakData {
        StreakData(
            currentStreak: 0,
            bestStreak: 0,
            lastActivityDate: nil,
            streakStartDate: nil,
            isAtRisk: false,
            freezesAvailable: 0,
            freezeActive: false,
            activeDays: []
        )
    }
}

// MARK: - Streak Milestones

extension StreakData {
    /// Standard milestone values
    static let milestones = [7, 30, 50, 100, 200, 365, 500, 1000]

    /// Whether current streak is a milestone
    var isMilestone: Bool {
        Self.milestones.contains(currentStreak)
    }

    /// Next milestone to achieve
    var nextMilestone: Int? {
        Self.milestones.first { $0 > currentStreak }
    }

    /// Progress toward next milestone (0.0 to 1.0)
    var progressToNextMilestone: Double {
        guard let next = nextMilestone else { return 1.0 }
        let previous = Self.milestones.last { $0 < currentStreak } ?? 0
        let range = next - previous
        let progress = currentStreak - previous
        return Double(progress) / Double(range)
    }
}

// MARK: - Streak Calculation (Pure Logic)

extension StreakData {
    /// Calculate updated streak after recording activity on a given date.
    /// Pure function: takes current state + date, returns new state.
    static func calculateUpdatedStreak(from current: StreakData, on date: Date = Date()) -> StreakData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        if let lastActivity = current.lastActivityDate,
           calendar.isDate(lastActivity, inSameDayAs: today) {
            return current
        }

        var newCurrentStreak = current.currentStreak
        var newStreakStart = current.streakStartDate

        if let lastActivity = current.lastActivityDate {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

            if calendar.isDate(lastActivity, inSameDayAs: yesterday) {
                newCurrentStreak += 1
            } else {
                newCurrentStreak = 1
                newStreakStart = today
            }
        } else {
            newCurrentStreak = 1
            newStreakStart = today
        }

        let newBestStreak = max(current.bestStreak, newCurrentStreak)

        var newActiveDays = current.activeDays.filter {
            calendar.dateComponents([.day], from: $0, to: today).day ?? 32 < 31
        }
        newActiveDays.append(today)

        return StreakData(
            currentStreak: newCurrentStreak,
            bestStreak: newBestStreak,
            lastActivityDate: today,
            streakStartDate: newStreakStart,
            isAtRisk: false,
            freezesAvailable: 0,
            freezeActive: false,
            activeDays: newActiveDays
        )
    }
}
