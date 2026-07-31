import Foundation
import Security

/// Plan-usage numbers, fetched the same way Claude Code's /usage screen gets
/// them: the OAuth token from the login keychain, against Anthropic's usage
/// endpoint.
///
/// Worth knowing:
///  * The keychain read triggers a one-time macOS prompt naming F1DockPet —
///    "Always Allow" makes it silent afterwards. The token never leaves the
///    machine except to api.anthropic.com, its own service.
///  * This endpoint reports billing state — calling it costs no tokens.
@MainActor
enum UsageService {

    struct Row {
        let label: String
        let percent: Int
        let resets: String
    }

    private(set) static var rows: [Row] = []
    private(set) static var error: String?
    private static var lastFetch: Date = .distantPast
    private static var inFlight = false

    /// Refresh if the cache is stale (>60s). `onChange` fires only when new
    /// data (or a new error) actually lands.
    static func refresh(onChange: @escaping @MainActor () -> Void) {
        guard !inFlight, Date().timeIntervalSince(lastFetch) > 60 else { return }

        guard let token = accessToken() else {
            error = "No Claude Code credentials readable from the keychain.\n\nIf macOS just asked about keychain access, approve it (Always Allow) and reopen this tab."
            lastFetch = Date()
            onChange()
            return
        }

        inFlight = true
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, netError in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    inFlight = false
                    lastFetch = Date()
                    defer { onChange() }

                    if let netError { error = netError.localizedDescription; return }
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        error = "Usage endpoint answered \(http.statusCode)."
                        return
                    }
                    guard let data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { error = "Unreadable reply from the usage endpoint."; return }

                    let parsed = parse(json)
                    if parsed.isEmpty {
                        error = "No limit data in the reply — keys: \(json.keys.sorted().joined(separator: ", "))"
                    } else {
                        rows = parsed
                        error = nil
                    }
                }
            }
        }.resume()
    }

    // MARK: - parsing

    /// The endpoint's shape isn't documented, so parse structurally: anything
    /// carrying a `utilization` number is a limit row, wherever it nests.
    private static func parse(_ json: [String: Any]) -> [Row] {
        let names: [String: (Int, String)] = [
            "five_hour": (0, "5-hour limit"),
            "seven_day": (1, "Weekly · all models"),
            "seven_day_sonnet": (2, "Weekly · Sonnet"),
            "seven_day_opus": (3, "Weekly · Opus"),
            "seven_day_fable": (4, "Weekly · Fable"),
        ]

        var found: [(order: Int, row: Row)] = []
        func walk(_ object: [String: Any], depth: Int) {
            for (key, value) in object {
                guard let dict = value as? [String: Any] else { continue }
                if let raw = dict["utilization"] as? Double {
                    let percent = Int((raw <= 1 ? raw * 100 : raw).rounded())
                    let (order, label) = names[key]
                        ?? (9, key.replacingOccurrences(of: "_", with: " "))
                    found.append((order, Row(label: label,
                                             percent: min(100, max(0, percent)),
                                             resets: resetText(dict["resets_at"]))))
                } else if depth < 3 {
                    walk(dict, depth: depth + 1)
                }
            }
        }
        walk(json, depth: 0)
        return found.sorted { $0.order < $1.order }.map(\.row)
    }

    private static func resetText(_ value: Any?) -> String {
        var date: Date?
        if let s = value as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: s)
            if date == nil {
                iso.formatOptions = [.withInternetDateTime]
                date = iso.date(from: s)
            }
        } else if let n = value as? Double {
            date = Date(timeIntervalSince1970: n)
        }
        guard let date else { return "" }

        let interval = date.timeIntervalSinceNow
        if interval < 0 { return "resetting…" }
        if interval < 3600 { return "resets in \(Int(interval / 60)) min" }
        if interval < 86_400 {
            let h = Int(interval) / 3600
            let m = (Int(interval) % 3600) / 60
            return "resets in \(h) h \(m) min"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE HH:mm"
        return "resets \(fmt.string(from: date))"
    }

    // MARK: - local activity KPIs

    struct Stat {
        let label: String
        let value: String
    }

    /// One bar of the Monday-to-Sunday histogram. Future days carry a
    /// projection from past same-weekday activity instead of a count.
    struct DayBar {
        let label: String
        let count: Int
        let projected: Bool
        let isToday: Bool
    }

    private static var statCache: [Stat] = []
    private static var histCache: [DayBar] = []
    private static var statsComputed: Date = .distantPast

    static func weekHistogram() -> [DayBar] {
        _ = stats()          // shares the cache; stats() recomputes both
        return histCache
    }

    /// Activity numbers computed from local files — prompt history, session
    /// transcripts — at zero cost. Cached for a minute.
    static func stats() -> [Stat] {
        if Date().timeIntervalSince(statsComputed) < 60 { return statCache }
        statsComputed = Date()

        let home = NSHomeDirectory()
        let calendar = Calendar.current
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        var out: [Stat] = []

        // Prompts, from Claude Code's own history file — counted per day so
        // the same pass feeds the weekly histogram.
        var promptsToday = 0, promptsWeek = 0
        var perDay: [Date: Int] = [:]
        if let text = try? String(contentsOfFile: home + "/.claude/history.jsonl", encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let raw = json["timestamp"] as? Double else { continue }
                let date = Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
                if calendar.isDateInToday(date) { promptsToday += 1 }
                if date > weekAgo { promptsWeek += 1 }
                perDay[calendar.startOfDay(for: date), default: 0] += 1
            }
        }
        out.append(Stat(label: "Prompts", value: "\(promptsToday) today · \(promptsWeek) this week"))
        histCache = buildHistogram(perDay: perDay, calendar: calendar)

        // Sessions and their footprint, from the transcripts on disk.
        var sessionsToday = 0, sessionsWeek = 0, sessionsTotal = 0
        var bytes: Int64 = 0
        let projects = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects")
        if let walker = FileManager.default.enumerator(
            at: projects, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                if url.path.contains("claude-mem") { continue }   // machinery, not chats
                sessionsTotal += 1
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                bytes += Int64(values?.fileSize ?? 0)
                if let modified = values?.contentModificationDate {
                    if calendar.isDateInToday(modified) { sessionsToday += 1 }
                    if modified > weekAgo { sessionsWeek += 1 }
                }
            }
        }
        out.append(Stat(label: "Sessions",
                        value: "\(sessionsToday) today · \(sessionsWeek) this week · \(sessionsTotal) total"))
        out.append(Stat(label: "Transcripts",
                        value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " on disk"))

        // The session the hooks are following right now.
        if let live = StateChannel.readSession(),
           let info = Transcript.contextInfo(id: live.id, cwd: live.cwd) {
            out.append(Stat(label: "Live session", value: info.summary))
        }

        statCache = out
        return out
    }

    /// Monday-to-Sunday of the current week. Past days show real counts;
    /// future days get an estimate from past same-weekday averages, falling
    /// back to the overall daily mean when a weekday has no history yet.
    private static func buildHistogram(perDay: [Date: Int], calendar: Calendar) -> [DayBar] {
        var iso = Calendar(identifier: .iso8601)   // weeks start on Monday
        iso.timeZone = calendar.timeZone
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = iso.dateInterval(of: .weekOfYear, for: Date())?.start
        else { return [] }

        var weekdayTotals = [Int](repeating: 0, count: 7)
        var weekdaySamples = [Int](repeating: 0, count: 7)
        for (day, count) in perDay where day < weekStart {
            let index = (iso.component(.weekday, from: day) + 5) % 7   // Mon = 0
            weekdayTotals[index] += count
            weekdaySamples[index] += 1
        }
        let overallMean = perDay.isEmpty ? 0
            : perDay.values.reduce(0, +) / perDay.count

        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        var bars: [DayBar] = []
        for offset in 0..<7 {
            guard let day = iso.date(byAdding: .day, value: offset, to: weekStart)
            else { continue }
            if day <= today {
                bars.append(DayBar(label: labels[offset], count: perDay[day] ?? 0,
                                   projected: false, isToday: day == today))
            } else {
                let estimate = weekdaySamples[offset] > 0
                    ? weekdayTotals[offset] / weekdaySamples[offset]
                    : overallMean
                bars.append(DayBar(label: labels[offset], count: estimate,
                                   projected: true, isToday: false))
            }
        }
        return bars
    }

    // MARK: - keychain

    private static func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }
}
