import Foundation

struct PersistedState: Codable {
    var salaryType: String = SalaryType.annual.rawValue
    var salaryAmount: Double = 0
    var paydayDay: Int = 25
    var isRunning: Bool = false
    var todayAmount: Double = 0
    var cumulativeAmount: Double = 0
    var lastResetDate: Double = 0
    var payPeriodStart: Double = 0
    var lastTickDate: Double = 0
    var stoppedAt: Double = 0
    var lastStartDate: Double = 0
    var lastStopDate: Double = 0
    var dailyHistory: [String: Double] = [:]
    var itemName: String = "피자헛 수퍼슈림프 L"
    var itemPrice: Double = 23900
}

/// Persists to a fixed file under Application Support instead of UserDefaults keyed by
/// CFBundleIdentifier — switching between `swift run` (no bundle id) and the packaged
/// .app, or any future rename, used to look like "money history got wiped on update".
enum Storage {
    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("WolgeupMeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }()

    static func load() -> PersistedState {
        if let data = try? Data(contentsOf: fileURL),
           let state = try? JSONDecoder().decode(PersistedState.self, from: data) {
            return state
        }
        return migrateFromUserDefaults() ?? PersistedState()
    }

    static func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// One-time recovery for anyone upgrading from a version that stored to UserDefaults
    /// (either the dev `swift run` domain or the packaged app's bundle-id domain).
    private static func migrateFromUserDefaults() -> PersistedState? {
        let candidates = [UserDefaults(suiteName: "com.tpgusgh.timeismoney"), UserDefaults.standard]
        for defaults in candidates {
            guard let defaults,
                  defaults.object(forKey: "salaryAmount") != nil || defaults.object(forKey: "dailyHistory") != nil
            else { continue }

            var state = PersistedState()
            state.salaryType = defaults.string(forKey: "salaryType") ?? state.salaryType
            state.salaryAmount = defaults.double(forKey: "salaryAmount")
            let payday = defaults.integer(forKey: "paydayDay")
            state.paydayDay = payday > 0 ? payday : state.paydayDay
            state.isRunning = defaults.bool(forKey: "isRunning")
            state.todayAmount = defaults.double(forKey: "todayAmount")
            state.cumulativeAmount = defaults.double(forKey: "cumulativeAmount")
            state.lastResetDate = defaults.double(forKey: "lastResetDate")
            state.payPeriodStart = defaults.double(forKey: "payPeriodStart")
            state.lastTickDate = defaults.double(forKey: "lastTickDate")
            state.stoppedAt = defaults.double(forKey: "stoppedAt")
            state.lastStartDate = defaults.double(forKey: "lastStartDate")
            state.lastStopDate = defaults.double(forKey: "lastStopDate")
            state.dailyHistory = defaults.dictionary(forKey: "dailyHistory") as? [String: Double] ?? [:]
            save(state)
            return state
        }
        return nil
    }
}
