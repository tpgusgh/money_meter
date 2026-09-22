import Foundation

struct AvailableUpdate {
    let version: String
    let url: URL
}

enum UpdateChecker {
    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/tpgusgh/money_meter/releases/latest")!

    /// Compares latest release info from GitHub. `currentVersion` comes from the caller
    /// (CFBundleShortVersionString) so this stays testable without touching Bundle.main.
    static func checkForUpdate(currentVersion: String, completion: @escaping (AvailableUpdate?) -> Void) {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let htmlURLString = json["html_url"] as? String,
                  let htmlURL = URL(string: htmlURLString)
            else {
                completion(nil)
                return
            }
            let latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let update = isNewer(latestVersion, than: currentVersion) ? AvailableUpdate(version: latestVersion, url: htmlURL) : nil
            DispatchQueue.main.async { completion(update) }
        }.resume()
    }

    /// Compares dotted version strings numerically (e.g. "1.0.10" > "1.0.9", unlike string compare).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let partsA = a.split(separator: ".").map { Int($0) ?? 0 }
        let partsB = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(partsA.count, partsB.count) {
            let x = i < partsA.count ? partsA[i] : 0
            let y = i < partsB.count ? partsB[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
