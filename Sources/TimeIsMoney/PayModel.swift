import Foundation
import Combine

final class PayModel: ObservableObject {
    @Published private(set) var salaryType: SalaryType
    @Published private(set) var salaryAmount: Double
    @Published private(set) var paydayDay: Int
    @Published private(set) var isRunning: Bool
    @Published private(set) var todayAmount: Double
    @Published private(set) var cumulativeAmount: Double
    @Published private(set) var lastStartDate: Date?
    @Published private(set) var lastStopDate: Date?
    /// Per-day earnings ("yyyy-MM-dd" -> won), independent of the 3h idle reset on
    /// `todayAmount` — this is what the calendar view reads. Pruned to the last
    /// `PayCalculator.historyRetentionDays` days whenever a new day starts.
    @Published private(set) var dailyHistory: [String: Double]
    @Published private(set) var itemName: String
    @Published private(set) var itemPrice: Double
    /// Session-only (not persisted): whether the floating panel shows full controls
    /// or just collapses to the running total. Toggled from the status bar icon.
    @Published var showDetail: Bool = true
    /// Session-only: whether the panel is showing the calendar instead of detail controls.
    @Published var showCalendar: Bool = false
    /// Session-only: set once from AppDelegate after a GitHub release check finds a newer tag.
    @Published var availableUpdate: AvailableUpdate?

    static let idleResetInterval: TimeInterval = 3 * 3600 // "오늘" clears 3h after work stops

    private var timer: Timer?
    private var idleResetTimer: Timer?
    private var lastResetDate: Date
    private var payPeriodStart: Date
    private var lastTickDate: Date
    private var stoppedAt: Date?

    init() {
        let stored = Storage.load()
        salaryType = SalaryType(rawValue: stored.salaryType) ?? .annual
        salaryAmount = stored.salaryAmount
        let resolvedPayday = stored.paydayDay > 0 ? stored.paydayDay : 25
        paydayDay = resolvedPayday
        // Always start stopped — a quit (crash, force-quit, Cmd+Q) shouldn't leave the
        // meter silently running until the user notices. applicationWillTerminate calls
        // stop() on a clean quit, so a leftover `true` here only happens after an unclean one.
        isRunning = false
        todayAmount = stored.todayAmount
        cumulativeAmount = stored.cumulativeAmount
        lastStartDate = stored.lastStartDate > 0 ? Date(timeIntervalSince1970: stored.lastStartDate) : nil
        lastStopDate = stored.lastStopDate > 0 ? Date(timeIntervalSince1970: stored.lastStopDate) : nil
        dailyHistory = stored.dailyHistory
        itemName = stored.itemName
        itemPrice = stored.itemPrice

        let now = Date()
        lastResetDate = stored.lastResetDate > 0 ? Date(timeIntervalSince1970: stored.lastResetDate) : now
        payPeriodStart = stored.payPeriodStart > 0
            ? Date(timeIntervalSince1970: stored.payPeriodStart)
            : PayCalculator.currentPeriodStart(now: now, payday: resolvedPayday)
        lastTickDate = stored.lastTickDate > 0 ? Date(timeIntervalSince1970: stored.lastTickDate) : now
        // If it was still marked running when the process died, the last tick is the
        // closest thing to a real "stopped at" — otherwise today's idle-clear timer would
        // never start even though nothing has been accruing since.
        stoppedAt = stored.isRunning
            ? Date(timeIntervalSince1970: stored.lastTickDate)
            : (stored.stoppedAt > 0 ? Date(timeIntervalSince1970: stored.stoppedAt) : nil)

        applyRollovers(now: now)

        if let stoppedAt {
            if PayCalculator.shouldClearIdleToday(stoppedAt: stoppedAt, now: now, interval: Self.idleResetInterval) {
                resetTodayFromIdle()
            } else {
                scheduleIdleReset(after: Self.idleResetInterval - now.timeIntervalSince(stoppedAt))
            }
        }
        persist() // write back isRunning: false even if it was left `true` in the file
    }

    var perSecondRate: Double {
        PayCalculator.perSecondRate(type: salaryType, amount: salaryAmount)
    }

    func toggleDetail() {
        showDetail.toggle()
    }

    /// Applies edited settings from the panel's 저장 button. Re-anchors the pay-period
    /// marker to the new payday without zeroing progress already earned this period.
    func applySettings(type: SalaryType, amount: Double, payday: Int, itemName: String, itemPrice: Double) {
        salaryType = type
        salaryAmount = amount
        self.itemName = itemName.isEmpty ? self.itemName : itemName
        self.itemPrice = itemPrice > 0 ? itemPrice : self.itemPrice

        let clampedPayday = min(max(payday, 1), 31)
        if clampedPayday != paydayDay {
            paydayDay = clampedPayday
            payPeriodStart = PayCalculator.currentPeriodStart(now: Date(), payday: paydayDay)
        }
        persist()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let now = Date()
        lastTickDate = now
        lastStartDate = now
        stoppedAt = nil
        idleResetTimer?.invalidate()
        idleResetTimer = nil
        scheduleTimer()
        persist()
    }

    func stop() {
        guard isRunning else { return }
        tick()
        isRunning = false
        timer?.invalidate()
        timer = nil

        let now = Date()
        lastStopDate = now
        stoppedAt = now
        scheduleIdleReset(after: Self.idleResetInterval)
        persist()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }

    private func scheduleIdleReset(after interval: TimeInterval) {
        idleResetTimer?.invalidate()
        let idleTimer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.resetTodayFromIdle()
        }
        RunLoop.current.add(idleTimer, forMode: .common)
        idleResetTimer = idleTimer
    }

    private func resetTodayFromIdle() {
        todayAmount = 0
        stoppedAt = nil
        idleResetTimer = nil
        persist()
    }

    /// Rolls "오늘"/누적 over if a day or pay period boundary was crossed. Runs both on
    /// every tick and once at launch, so being closed overnight still resets correctly
    /// even though nothing ticked while it was shut.
    private func applyRollovers(now: Date) {
        if PayCalculator.shouldResetForNewDay(lastResetDate: lastResetDate, now: now) {
            todayAmount = 0
            lastResetDate = now
            dailyHistory = dailyHistory.filter { PayCalculator.isWithinRetention(dayKey: $0.key, now: now) }
        }
        if PayCalculator.shouldResetForNewPayPeriod(storedPeriodStart: payPeriodStart, now: now, payday: paydayDay) {
            cumulativeAmount = 0
            payPeriodStart = PayCalculator.currentPeriodStart(now: now, payday: paydayDay)
        }
    }

    /// Removes a single day's entry from the calendar history (e.g. a mis-tracked day).
    func deleteHistory(for date: Date) {
        let key = PayCalculator.dayKey(for: date)
        guard dailyHistory[key] != nil else { return }
        dailyHistory.removeValue(forKey: key)
        persist()
    }

    private func tick() {
        let now = Date()
        applyRollovers(now: now)

        let elapsed = now.timeIntervalSince(lastTickDate)
        let amount = perSecondRate * elapsed
        todayAmount += amount
        cumulativeAmount += amount
        lastTickDate = now

        let key = PayCalculator.dayKey(for: now)
        dailyHistory[key, default: 0] += amount

        persist()
    }

    private func persist() {
        Storage.save(PersistedState(
            salaryType: salaryType.rawValue,
            salaryAmount: salaryAmount,
            paydayDay: paydayDay,
            isRunning: isRunning,
            todayAmount: todayAmount,
            cumulativeAmount: cumulativeAmount,
            lastResetDate: lastResetDate.timeIntervalSince1970,
            payPeriodStart: payPeriodStart.timeIntervalSince1970,
            lastTickDate: lastTickDate.timeIntervalSince1970,
            stoppedAt: stoppedAt?.timeIntervalSince1970 ?? 0,
            lastStartDate: lastStartDate?.timeIntervalSince1970 ?? 0,
            lastStopDate: lastStopDate?.timeIntervalSince1970 ?? 0,
            dailyHistory: dailyHistory,
            itemName: itemName,
            itemPrice: itemPrice
        ))
    }
}
