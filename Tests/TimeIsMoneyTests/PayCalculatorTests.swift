import XCTest
@testable import TimeIsMoney

final class PayCalculatorTests: XCTestCase {
    func testAnnualPerSecondRate() {
        // 60,000,000 won/year -> 5,000,000/month -> /209h -> /3600s
        let rate = PayCalculator.perSecondRate(type: .annual, amount: 60_000_000)
        let expected = (60_000_000.0 / 12 / 209 / 3600)
        XCTAssertEqual(rate, expected, accuracy: 0.0001)
    }

    func testMonthlyPerSecondRate() {
        let rate = PayCalculator.perSecondRate(type: .monthly, amount: 5_000_000)
        let expected = (5_000_000.0 / 209 / 3600)
        XCTAssertEqual(rate, expected, accuracy: 0.0001)
    }

    func testHourlyPerSecondRate() {
        let rate = PayCalculator.perSecondRate(type: .hourly, amount: 12_000)
        XCTAssertEqual(rate, 12_000.0 / 3600, accuracy: 0.0001)
    }

    func testZeroOrNegativeAmountYieldsZeroRate() {
        XCTAssertEqual(PayCalculator.perSecondRate(type: .monthly, amount: 0), 0)
        XCTAssertEqual(PayCalculator.perSecondRate(type: .monthly, amount: -100), 0)
    }

    func testShouldResetForNewDay() {
        let calendar = Calendar.current
        let now = Date()
        XCTAssertFalse(PayCalculator.shouldResetForNewDay(lastResetDate: now, now: now, calendar: calendar))

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(PayCalculator.shouldResetForNewDay(lastResetDate: yesterday, now: now, calendar: calendar))
    }

    func testCurrentPeriodStartSameMonthAfterPayday() {
        var comps = DateComponents(year: 2026, month: 9, day: 22)
        let calendar = Calendar.current
        let now = calendar.date(from: comps)!
        let start = PayCalculator.currentPeriodStart(now: now, payday: 15, calendar: calendar)
        comps.day = 15
        XCTAssertEqual(start, calendar.date(from: comps)!)
    }

    func testCurrentPeriodStartRollsBackToPreviousMonthBeforePayday() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let start = PayCalculator.currentPeriodStart(now: now, payday: 25, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        XCTAssertEqual(start, expected)
    }

    func testCurrentPeriodStartClampsToShortMonth() {
        let calendar = Calendar.current
        // Feb 2026 has 28 days; payday 31 should clamp to Feb 28.
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        let start = PayCalculator.currentPeriodStart(now: now, payday: 31, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 2, day: 28))!
        XCTAssertEqual(start, expected)
    }

    func testShouldClearIdleToday() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-2 * 3600)
        let fourHoursAgo = now.addingTimeInterval(-4 * 3600)
        XCTAssertFalse(PayCalculator.shouldClearIdleToday(stoppedAt: twoHoursAgo, now: now, interval: 3 * 3600))
        XCTAssertTrue(PayCalculator.shouldClearIdleToday(stoppedAt: fourHoursAgo, now: now, interval: 3 * 3600))
    }

    func testShouldResetForNewPayPeriod() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let stillThisPeriod = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        XCTAssertFalse(PayCalculator.shouldResetForNewPayPeriod(storedPeriodStart: stillThisPeriod, now: now, payday: 25, calendar: calendar))

        let previousPeriod = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        XCTAssertTrue(PayCalculator.shouldResetForNewPayPeriod(storedPeriodStart: previousPeriod, now: now, payday: 25, calendar: calendar))
    }
}

final class FormatWonTests: XCTestCase {
    func testBelowTenThousandShowsPlainWon() {
        XCTAssertEqual(formatWon(3245), "₩3,245")
        XCTAssertEqual(formatWon(0), "₩0")
    }

    func testAtOrAboveTenThousandShowsManUnit() {
        XCTAssertEqual(formatWon(10_000), "₩1만원")
        XCTAssertEqual(formatWon(100_000), "₩10만원")
        XCTAssertEqual(formatWon(15_000), "₩1.5만원")
    }

    func testFormatWonBrokenSplitsIntoManAndRemainder() {
        XCTAssertEqual(formatWonBroken(10_090), "1만90원")
        XCTAssertEqual(formatWonBroken(60_000_000), "6000만원")
        XCTAssertEqual(formatWonBroken(12_345), "1만2,345원")
        XCTAssertEqual(formatWonBroken(100_000_000), "1억원")
        XCTAssertEqual(formatWonBroken(90), "90원")
        XCTAssertEqual(formatWonBroken(0), "0원")
    }
}
