import Foundation
import Combine

final class PayModel: ObservableObject {
    @Published private(set) var salaryType: SalaryType
    @Published private(set) var salaryAmount: Double
    @Published private(set) var paydayDay: Int
    @Published private(set) var isRunning: Bool
    @Published private(set) var todayAmount: Double
    @Published private(set) var cumulativeAmount: Double
    /// Session-only (not persisted): whether the floating panel shows full controls
    /// or just collapses to the running total. Toggled from the status bar icon.
    @Published var showDetail: Bool = true

    static let idleResetInterval: TimeInterval = 3 * 3600 // "오늘" clears 3h after work stops

    private var timer: Timer?
    private var idleResetTimer: Timer?
    private var lastResetDate: Date
    private var payPeriodStart: Date
    private var lastTickDate: Date
    private let defaults: UserDefaults

    private enum Keys {
        static let salaryType = "salaryType"
        static let salaryAmount = "salaryAmount"
        static let paydayDay = "paydayDay"
        static let isRunning = "isRunning"
        static let todayAmount = "todayAmount"
        static let cumulativeAmount = "cumulativeAmount"
        static let lastResetDate = "lastResetDate"
        static let payPeriodStart = "payPeriodStart"
        static let lastTickDate = "lastTickDate"
        static let stoppedAt = "stoppedAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        salaryType = SalaryType(rawValue: defaults.string(forKey: Keys.salaryType) ?? "") ?? .annual
        salaryAmount = defaults.double(forKey: Keys.salaryAmount)
        let storedPayday = defaults.integer(forKey: Keys.paydayDay)
        let resolvedPayday = storedPayday > 0 ? storedPayday : 25
        paydayDay = resolvedPayday
        isRunning = defaults.bool(forKey: Keys.isRunning)
        todayAmount = defaults.double(forKey: Keys.todayAmount)
        cumulativeAmount = defaults.double(forKey: Keys.cumulativeAmount)

        let now = Date()
        let storedReset = defaults.double(forKey: Keys.lastResetDate)
        lastResetDate = storedReset > 0 ? Date(timeIntervalSince1970: storedReset) : now
        let storedPeriodStart = defaults.double(forKey: Keys.payPeriodStart)
        payPeriodStart = storedPeriodStart > 0
            ? Date(timeIntervalSince1970: storedPeriodStart)
            : PayCalculator.currentPeriodStart(now: now, payday: resolvedPayday)
        let storedTick = defaults.double(forKey: Keys.lastTickDate)
        lastTickDate = storedTick > 0 ? Date(timeIntervalSince1970: storedTick) : now

        if isRunning {
            tick() // catch up on elapsed time since the app was last closed
            scheduleTimer()
        } else {
            let storedStoppedAt = defaults.double(forKey: Keys.stoppedAt)
            if storedStoppedAt > 0 {
                let stoppedDate = Date(timeIntervalSince1970: storedStoppedAt)
                if PayCalculator.shouldClearIdleToday(stoppedAt: stoppedDate, now: now, interval: Self.idleResetInterval) {
                    resetTodayFromIdle()
                } else {
                    let elapsed = now.timeIntervalSince(stoppedDate)
                    scheduleIdleReset(after: Self.idleResetInterval - elapsed)
                }
            }
        }
    }

    var perSecondRate: Double {
        PayCalculator.perSecondRate(type: salaryType, amount: salaryAmount)
    }

    func toggleDetail() {
        showDetail.toggle()
    }

    /// Applies edited settings from the panel's 저장 button. Re-anchors the pay-period
    /// marker to the new payday without zeroing progress already earned this period.
    func applySettings(type: SalaryType, amount: Double, payday: Int) {
        salaryType = type
        salaryAmount = amount
        defaults.set(salaryType.rawValue, forKey: Keys.salaryType)
        defaults.set(salaryAmount, forKey: Keys.salaryAmount)

        let clampedPayday = min(max(payday, 1), 31)
        if clampedPayday != paydayDay {
            paydayDay = clampedPayday
            payPeriodStart = PayCalculator.currentPeriodStart(now: Date(), payday: paydayDay)
            defaults.set(paydayDay, forKey: Keys.paydayDay)
            defaults.set(payPeriodStart.timeIntervalSince1970, forKey: Keys.payPeriodStart)
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTickDate = Date()
        defaults.set(isRunning, forKey: Keys.isRunning)
        defaults.set(lastTickDate.timeIntervalSince1970, forKey: Keys.lastTickDate)
        defaults.removeObject(forKey: Keys.stoppedAt)
        idleResetTimer?.invalidate()
        idleResetTimer = nil
        scheduleTimer()
    }

    func stop() {
        guard isRunning else { return }
        tick()
        isRunning = false
        timer?.invalidate()
        timer = nil
        defaults.set(isRunning, forKey: Keys.isRunning)

        let now = Date()
        defaults.set(now.timeIntervalSince1970, forKey: Keys.stoppedAt)
        scheduleIdleReset(after: Self.idleResetInterval)
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
        defaults.set(0, forKey: Keys.todayAmount)
        defaults.removeObject(forKey: Keys.stoppedAt)
        idleResetTimer = nil
    }

    private func tick() {
        let now = Date()
        if PayCalculator.shouldResetForNewDay(lastResetDate: lastResetDate, now: now) {
            todayAmount = 0
            lastResetDate = now
            defaults.set(lastResetDate.timeIntervalSince1970, forKey: Keys.lastResetDate)
        }
        if PayCalculator.shouldResetForNewPayPeriod(storedPeriodStart: payPeriodStart, now: now, payday: paydayDay) {
            cumulativeAmount = 0
            payPeriodStart = PayCalculator.currentPeriodStart(now: now, payday: paydayDay)
            defaults.set(payPeriodStart.timeIntervalSince1970, forKey: Keys.payPeriodStart)
        }

        let elapsed = now.timeIntervalSince(lastTickDate)
        let amount = perSecondRate * elapsed
        todayAmount += amount
        cumulativeAmount += amount
        lastTickDate = now

        defaults.set(todayAmount, forKey: Keys.todayAmount)
        defaults.set(cumulativeAmount, forKey: Keys.cumulativeAmount)
        defaults.set(lastTickDate.timeIntervalSince1970, forKey: Keys.lastTickDate)
    }
}
