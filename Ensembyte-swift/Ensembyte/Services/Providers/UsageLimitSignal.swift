import Foundation

/// A provider saying the account's usage limit is spent, and when it comes back.
enum UsageLimitSignal {
    /// Whether an error message is the provider refusing to work until a usage limit resets.
    /// The first group is how Claude and Codex say it; the rest is what omp relays from
    /// Anthropic (an account's rate or spend limit, long-context credits), Google (an
    /// exhausted quota) and OpenAI-compatible providers.
    static func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("usage limit") || lower.contains("hit your limit") || lower.contains("usage_limit")
            || lower.contains("limit reached") || lower.contains("out of extra usage")
            || lower.contains("account's rate limit") || lower.contains("spend limit")
            || lower.contains("usage credits are required") || lower.contains("quota will reset")
            || lower.contains("exhausted your capacity") || lower.contains("resource_exhausted")
            || lower.contains("resource exhausted") || lower.contains("insufficient_quota")
            || lower.contains("out of credits")
    }

    /// The reset time an error message carries, when it does: a Unix timestamp after a bar
    /// ("usage limit reached|1757865600"), a clock time such as "resets 3pm" or "resets at
    /// 3:30 pm", taken as the next such time from now, or a wait (see `waitTime`) counted
    /// from now.
    static func resetTime(in text: String, now: Date = .now) -> Date? {
        if let match = text.range(of: #"\|\s*(\d{9,})"#, options: .regularExpression) {
            let digits = text[match].drop { !$0.isNumber }
            if let seconds = TimeInterval(digits) {
                // Some providers write milliseconds.
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1_000 : seconds)
            }
        }
        if let match = text.range(of: #"(?i)resets?(?:\s+at)?\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#, options: .regularExpression) {
            let clock = String(text[match])
            let numbers = clock.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            guard let hourText = numbers.first, var hour = Int(hourText) else { return nil }
            let minute = numbers.count > 1 ? Int(numbers[1]) ?? 0 : 0
            let isPM = clock.lowercased().hasSuffix("pm")
            if isPM, hour < 12 { hour += 12 }
            if !isPM, hour == 12 { hour = 0 }
            var calendar = Calendar.current
            if let zone = text.range(of: #"\(([A-Za-z_]+/[A-Za-z_]+)\)"#, options: .regularExpression),
               let timeZone = TimeZone(identifier: text[zone].trimmingCharacters(in: CharacterSet(charactersIn: "()"))) {
                calendar.timeZone = timeZone
            }
            let components = DateComponents(hour: hour, minute: minute)
            return calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime)
        }
        return waitTime(in: text).map { now.addingTimeInterval($0) }
    }

    /// The wait an error message names, the longest when it names several: "retry-after-ms=1800000"
    /// or "Provider requested 90000ms wait" (omp's own phrasing), "Try again in ~158 min",
    /// "Please retry in 12s", "reset after 18h31m10s", "resets in 3 days".
    static func waitTime(in text: String) -> TimeInterval? {
        var waits: [TimeInterval] = []
        for pattern in [#"(?i)retry-after-ms\s*[:=]\s*(\d+)"#, #"(?i)provider requested\s+(\d+)\s*ms\s+wait"#] {
            if let match = text.range(of: pattern, options: .regularExpression),
               let milliseconds = TimeInterval(text[match].filter(\.isNumber)) {
                waits.append(milliseconds / 1_000)
            }
        }
        for pattern in [#"(?i)(?:try again|retry)\s+in\s+~?\s*([0-9][0-9a-z .]*)"#, #"(?i)resets?\s+(?:after|in)\s+([0-9][0-9a-z .]*)"#] {
            var rest = text[...]
            while let match = rest.range(of: pattern, options: .regularExpression) {
                if let seconds = duration(in: String(rest[match])) { waits.append(seconds) }
                rest = rest[match.upperBound...]
            }
        }
        return waits.max().flatMap { $0 > 0 ? $0 : nil }
    }

    /// "18h31m10s", "2 hours 5 min", "3 days", "158 min", "12s": the units add up. A bare
    /// number carries no unit and so no duration, and `ms` is not minutes plus seconds.
    private static func duration(in text: String) -> TimeInterval? {
        let units: [(String, TimeInterval)] = [("d", 86_400), ("h", 3_600), ("m", 60), ("s", 1)]
        var total: TimeInterval = 0
        var found = false
        var rest = text.lowercased()[...]
        while let match = rest.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*(days?|d|hours?|hrs?|h|minutes?|mins?|m(?!s)|seconds?|secs?|s)(?![a-z])"#, options: .regularExpression) {
            let piece = rest[match]
            let digits = piece.prefix { $0.isNumber || $0 == "." }
            let unit = piece.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
            if let amount = TimeInterval(digits), let scale = units.first(where: { unit.hasPrefix($0.0) })?.1 {
                total += amount * scale
                found = true
            }
            rest = rest[match.upperBound...]
        }
        return found ? total : nil
    }

    /// "3:31 PM" today, "tomorrow at 9:00 AM" or "Thursday at 9:00 AM" further out.
    static func format(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(time)" }
        if let week = calendar.date(byAdding: .day, value: 6, to: .now), date < week {
            return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
