import AppKit

/// Checks GitHub for a newer release. No frameworks, no background agents —
/// one small JSON fetch, at most once a day on launch, plus whenever the
/// button in Preferences is clicked. The quiet daily check only ever says
/// something when there's actually an update.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(String)
        case failed
    }

    static let shared = UpdateChecker()

    @Published private(set) var status: Status = .idle

    static let releasesPageURL = URL(string: "https://github.com/layton-brewer/LiveWall/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/layton-brewer/LiveWall/releases/latest")!
    private static let lastCheckKey = "LiveWallLastUpdateCheck"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func checkIfDue() {
        if let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 24 * 60 * 60 {
            return
        }
        Task { await check(quiet: true) }
    }

    func checkNow() {
        Task { await check(quiet: false) }
    }

    private func check(quiet: Bool) async {
        if !quiet { status = .checking }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            var request = URLRequest(url: Self.apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = object["tag_name"] as? String else {
                if !quiet { status = .failed }
                return
            }
            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isVersion(remote, newerThan: currentVersion) {
                status = .updateAvailable(remote)
            } else if !quiet {
                status = .upToDate
            }
        } catch {
            if !quiet { status = .failed }
        }
    }

    /// Plain numeric comparison, piece by piece — "1.10" beats "1.9",
    /// which a string compare would get wrong.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
