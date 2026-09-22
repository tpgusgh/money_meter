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

    static let historyRetentionDays = 90

    private static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        return f
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        dayKeyFormatter(calendar: calendar).string(from: date)
    }

    /// Whether a "yyyy-MM-dd" history key is still within the retention window ending at `now`.
    static func isWithinRetention(dayKey: String, now: Date, retentionDays: Int = historyRetentionDays, calendar: Calendar = .current) -> Bool {
        guard let date = dayKeyFormatter(calendar: calendar).date(from: dayKey) else { return false }
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else { return true }
        return date >= calendar.startOfDay(for: cutoff)
    }
}
