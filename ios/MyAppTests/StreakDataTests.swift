//
//  StreakDataTests.swift
//  MyAppTests
//
//  Tests for streak data model and calculation logic.
//

import Testing
import Foundation
@testable import MyApp

// MARK: - Milestone Tests

@Suite("Streak Milestones")
struct StreakMilestoneTests {

    @Test("Known milestones are detected")
    func knownMilestones() {
        for milestone in [7, 30, 50, 100, 200, 365, 500, 1000] {
            let data = StreakData(
                currentStreak: milestone, bestStreak: milestone,
                lastActivityDate: nil, streakStartDate: nil,
                isAtRisk: false, freezesAvailable: 0, freezeActive: false, activeDays: []
            )
            #expect(data.isMilestone, "Expected \(milestone) to be a milestone")
        }
    }

    @Test("Non-milestone values are not flagged")
    func nonMilestones() {
        for value in [1, 5, 8, 29, 31, 99, 101] {
            let data = StreakData(
                currentStreak: value, bestStreak: value,
                lastActivityDate: nil, streakStartDate: nil,
                isAtRisk: false, freezesAvailable: 0, freezeActive: false, activeDays: []
            )
            #expect(!data.isMilestone, "Expected \(value) to not be a milestone")
        }
    }

    @Test("Next milestone returns correct target")
    func nextMilestone() {
        let data = StreakData(
            currentStreak: 10, bestStreak: 10,
            lastActivityDate: nil, streakStartDate: nil,
            isAtRisk: false, freezesAvailable: 0, freezeActive: false, activeDays: []
        )
        #expect(data.nextMilestone == 30)
    }

    @Test("Next milestone is nil past highest milestone")
    func nextMilestonePastMax() {
        let data = StreakData(
            currentStreak: 1001, bestStreak: 1001,
            lastActivityDate: nil, streakStartDate: nil,
            isAtRisk: false, freezesAvailable: 0, freezeActive: false, activeDays: []
        )
        #expect(data.nextMilestone == nil)
    }

    @Test("Progress to next milestone calculates correctly")
    func progressCalculation() {
        let data = StreakData(
            currentStreak: 15, bestStreak: 15,
            lastActivityDate: nil, streakStartDate: nil,
            isAtRisk: false, freezesAvailable: 0, freezeActive: false, activeDays: []
        )
        // Between milestone 7 and 30: progress = (15-7)/(30-7) = 8/23
        let expected = 8.0 / 23.0
        #expect(abs(data.progressToNextMilestone - expected) < 0.001)
    }
}

// MARK: - Streak Calculation Tests

@Suite("Streak Calculation")
struct StreakCalculationTests {

    private let calendar = Calendar.current

    private func makeDate(daysAgo: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!)
    }

    @Test("First activity starts a 1-day streak")
    func firstActivity() {
        let result = StreakData.calculateUpdatedStreak(from: .empty)

        #expect(result.currentStreak == 1)
        #expect(result.bestStreak == 1)
        #expect(result.lastActivityDate != nil)
        #expect(result.streakStartDate != nil)
        #expect(result.activeDays.count == 1)
    }

    @Test("Consecutive day increments streak")
    func consecutiveDay() {
        let yesterday = makeDate(daysAgo: 1)
        let existing = StreakData(
            currentStreak: 5, bestStreak: 5,
            lastActivityDate: yesterday, streakStartDate: makeDate(daysAgo: 5),
            isAtRisk: false, freezesAvailable: 0, freezeActive: false,
            activeDays: [yesterday]
        )

        let result = StreakData.calculateUpdatedStreak(from: existing)

        #expect(result.currentStreak == 6)
        #expect(result.bestStreak == 6)
    }

    @Test("Missed day resets streak to 1")
    func streakBreak() {
        let twoDaysAgo = makeDate(daysAgo: 2)
        let existing = StreakData(
            currentStreak: 10, bestStreak: 10,
            lastActivityDate: twoDaysAgo, streakStartDate: makeDate(daysAgo: 12),
            isAtRisk: false, freezesAvailable: 0, freezeActive: false,
            activeDays: [twoDaysAgo]
        )

        let result = StreakData.calculateUpdatedStreak(from: existing)

        #expect(result.currentStreak == 1)
        #expect(result.bestStreak == 10)
    }

    @Test("Same-day activity returns unchanged data")
    func alreadyLoggedToday() {
        let today = calendar.startOfDay(for: Date())
        let existing = StreakData(
            currentStreak: 3, bestStreak: 5,
            lastActivityDate: today, streakStartDate: makeDate(daysAgo: 3),
            isAtRisk: false, freezesAvailable: 0, freezeActive: false,
            activeDays: [today]
        )

        let result = StreakData.calculateUpdatedStreak(from: existing)

        #expect(result.currentStreak == existing.currentStreak)
        #expect(result.lastActivityDate == existing.lastActivityDate)
    }

    @Test("Best streak preserved when current streak is lower")
    func bestStreakPreserved() {
        let twoDaysAgo = makeDate(daysAgo: 2)
        let existing = StreakData(
            currentStreak: 3, bestStreak: 50,
            lastActivityDate: twoDaysAgo, streakStartDate: makeDate(daysAgo: 5),
            isAtRisk: false, freezesAvailable: 0, freezeActive: false,
            activeDays: []
        )

        let result = StreakData.calculateUpdatedStreak(from: existing)

        #expect(result.bestStreak == 50)
    }

    @Test("Active days older than 31 days are pruned")
    func activeDaysPruned() {
        let yesterday = makeDate(daysAgo: 1)
        let oldDay = makeDate(daysAgo: 35)
        let existing = StreakData(
            currentStreak: 2, bestStreak: 2,
            lastActivityDate: yesterday, streakStartDate: makeDate(daysAgo: 2),
            isAtRisk: false, freezesAvailable: 0, freezeActive: false,
            activeDays: [oldDay, yesterday]
        )

        let result = StreakData.calculateUpdatedStreak(from: existing)

        #expect(!result.activeDays.contains { calendar.isDate($0, inSameDayAs: oldDay) })
        #expect(result.activeDays.contains { calendar.isDate($0, inSameDayAs: yesterday) })
    }
}
