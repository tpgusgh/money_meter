import Foundation

enum SalaryType: String, Codable {
    case monthly
    case annual
    case hourly
}

enum PayCalculator {
    // ponytail: 209 = Korean statutory average monthly working hours (includes paid weekly holiday);
    // real contracts vary, no per-user override yet — add a settings field if this bites someone.
    static let standardMonthlyHours = 209.0

    static func perSecondRate(type: SalaryType, amount: Double) -> Double {
        guard amount.isFinite, amount > 0 else { return 0 }
        let hourly: Double
        switch type {
        case .hourly: hourly = amount
        case .monthly: hourly = amount / standardMonthlyHours
        case .annual: hourly = amount / 12 / standardMonthlyHours
        }
        return hourly / 3600
    }

    static func shouldResetForNewDay(lastResetDate: Date, now: Date, calendar: Calendar = .current) -> Bool {
        !calendar.isDate(lastResetDate, inSameDayAs: now)
    }

    /// Most recent payday on/before `date`, clamped to the last day of a short month (e.g. payday 31 -> Feb 28/29).
    static func currentPeriodStart(now: Date, payday: Int, calendar: Calendar = .current) -> Date {
        let day = calendar.component(.day, from: now)
        let daysInThisMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 28
        let effectivePayday = min(payday, daysInThisMonth)

        var comps = calendar.dateComponents([.year, .month], from: now)
        if day >= effectivePayday {
            comps.day = effectivePayday
            return calendar.date(from: comps) ?? now
        } else {
            let prevMonth = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            let daysInPrevMonth = calendar.range(of: .day, in: .month, for: prevMonth)?.count ?? 28
            var prevComps = calendar.dateComponents([.year, .month], from: prevMonth)
            prevComps.day = min(payday, daysInPrevMonth)
            return calendar.date(from: prevComps) ?? now
        }
    }

    static func shouldResetForNewPayPeriod(storedPeriodStart: Date, now: Date, payday: Int, calendar: Calendar = .current) -> Bool {
        currentPeriodStart(now: now, payday: payday, calendar: calendar) > storedPeriodStart
    }

    static func shouldClearIdleToday(stoppedAt: Date, now: Date, interval: TimeInterval) -> Bool {
        now.timeIntervalSince(stoppedAt) >= interval
    }
}
