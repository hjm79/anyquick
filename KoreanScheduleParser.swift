import Foundation

public struct ParsedSchedule: Equatable {
    public let title: String
    public let start: Date
    public let end: Date?
    public let allDay: Bool
    public let location: String?

    public init(title: String, start: Date, end: Date?, allDay: Bool, location: String?) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
    }
}

public struct KoreanScheduleParser {
    private let calendar: Calendar

    public init(calendar: Calendar = KoreanScheduleParser.defaultCalendar()) {
        self.calendar = calendar
    }

    public func parse(_ input: String, baseDate: Date = Date()) -> ParsedSchedule? {
        let text = normalizeSpaces(input)
        guard !text.isEmpty else { return nil }

        guard let parsedDate = parseDate(text: text, baseDate: baseDate) else {
            return nil
        }

        let parsedTime = parseTime(text: text)
        if parsedTime?.invalid == true {
            return nil
        }

        let location = extractLocation(text: text, anchorUTF16: parsedTime?.anchorUTF16)

        let start: Date
        let end: Date?
        let allDay: Bool

        if let parsedTime {
            var comps = calendar.dateComponents([.year, .month, .day], from: parsedDate.date)
            comps.hour = parsedTime.hour
            comps.minute = parsedTime.minute
            comps.second = 0

            guard var dateWithTime = calendar.date(from: comps) else { return nil }
            if parsedTime.addOneDay {
                guard let shifted = calendar.date(byAdding: .day, value: 1, to: dateWithTime) else { return nil }
                dateWithTime = shifted
            }
            start = dateWithTime
            end = nil
            allDay = false
        } else {
            let dayStart = calendar.startOfDay(for: parsedDate.date)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            start = dayStart
            end = nextDay
            allDay = true
        }

        let title = extractTitle(text: text, dateRegexes: parsedDate.consumedRegexes, timeRegexes: parsedTime?.consumedRegexes ?? [], location: location)
        guard !title.isEmpty else { return nil }

        return ParsedSchedule(title: title, start: start, end: end, allDay: allDay, location: location)
    }
}

private extension KoreanScheduleParser {
    static func defaultCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return cal
    }

    struct ParsedDate {
        let date: Date
        let consumedRegexes: [String]
    }

    struct ParsedTime {
        let hour: Int
        let minute: Int
        let addOneDay: Bool
        let invalid: Bool
        let consumedRegexes: [String]
        let anchorUTF16: Int?
    }

    func parseDate(text: String, baseDate: Date) -> ParsedDate? {
        let now = baseDate

        if let m = firstMatch(#"(\d{4})년\s*(\d{1,2})월\s*(\d{1,2})일"#, in: text) {
            guard let year = m.int(1), let month = m.int(2), let day = m.int(3),
                  let date = makeValidDate(year: year, month: month, day: day) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"내년\s*(\d{1,2})월\s*(\d{1,2})일"#, in: text) {
            guard let month = m.int(1), let day = m.int(2) else { return nil }
            let nowYear = calendar.component(.year, from: now)
            guard let date = makeValidDate(year: nowYear + 1, month: month, day: day) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"다음달\s*(\d{1,2})일"#, in: text) {
            guard let day = m.int(1) else { return nil }
            guard let monthStart = calendar.date(byAdding: .month, value: 1, to: startOfMonth(for: now)) else { return nil }
            let year = calendar.component(.year, from: monthStart)
            let month = calendar.component(.month, from: monthStart)
            guard let date = makeValidDate(year: year, month: month, day: day) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"(\d{1,2})월\s*(\d{1,2})일"#, in: text) {
            guard let month = m.int(1), let day = m.int(2) else { return nil }
            let currentYear = calendar.component(.year, from: now)
            guard let thisYearDate = makeValidDate(year: currentYear, month: month, day: day) else { return nil }

            let nowStart = calendar.startOfDay(for: now)
            let targetStart = calendar.startOfDay(for: thisYearDate)
            if targetStart < nowStart {
                guard let nextYearDate = makeValidDate(year: currentYear + 1, month: month, day: day) else { return nil }
                return ParsedDate(date: nextYearDate, consumedRegexes: [m.pattern])
            }
            return ParsedDate(date: thisYearDate, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"(오늘|내일)"#, in: text) {
            guard let token = m.group(1) else { return nil }
            let days = token == "내일" ? 1 : 0
            guard let date = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"(이번주|다음주)\s*(월요일|화요일|수요일|목요일|금요일|토요일|일요일)"#, in: text) {
            guard let weekToken = m.group(1), let weekdayToken = m.group(2),
                  let weekday = weekdayKoreanToCalendar(weekdayToken) else { return nil }
            let weekOffset = weekToken == "다음주" ? 1 : 0
            guard let date = resolveWeekday(weekday: weekday, baseDate: now, weekOffset: weekOffset, forceFuture: false) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        if let m = firstMatch(#"(월요일|화요일|수요일|목요일|금요일|토요일|일요일)"#, in: text) {
            guard let weekdayToken = m.group(1), let weekday = weekdayKoreanToCalendar(weekdayToken) else { return nil }
            guard let date = resolveWeekday(weekday: weekday, baseDate: now, weekOffset: 0, forceFuture: true) else { return nil }
            return ParsedDate(date: date, consumedRegexes: [m.pattern])
        }

        return nil
    }

    func parseTime(text: String) -> ParsedTime? {
        let ampmMatch = firstMatch(#"(오전|오후|밤)"#, in: text)
        let ampm = ampmMatch?.group(1)

        if let colon = firstMatch(#"(\d{1,2}):(\d{2})"#, in: text) {
            guard let hour = colon.int(1), let minute = colon.int(2) else { return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil) }
            if ampm != nil {
                return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil)
            }
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil)
            }
            return ParsedTime(hour: hour, minute: minute, addOneDay: false, invalid: false, consumedRegexes: [colon.pattern], anchorUTF16: colon.range.location)
        }

        if let half = firstMatch(#"(오전|오후|밤)?\s*(\d{1,2})시\s*반(?:\s*(?:에|까지|쯤|경))?"#, in: text) {
            guard let rawHour = half.int(2) else { return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil) }
            let token = half.group(1) ?? ampm
            guard let converted = convertHour(rawHour: rawHour, meridiem: token) else {
                return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil)
            }
            return ParsedTime(hour: converted.hour, minute: 30, addOneDay: converted.addOneDay, invalid: false, consumedRegexes: [half.pattern], anchorUTF16: half.range.location)
        }

        if let hourOnly = firstMatch(#"(오전|오후|밤)?\s*(\d{1,2})시(?:\s*(?:에|까지|쯤|경))?"#, in: text) {
            guard let rawHour = hourOnly.int(2) else { return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil) }
            let token = hourOnly.group(1) ?? ampm
            guard let converted = convertHour(rawHour: rawHour, meridiem: token) else {
                return ParsedTime(hour: 0, minute: 0, addOneDay: false, invalid: true, consumedRegexes: [], anchorUTF16: nil)
            }
            return ParsedTime(hour: converted.hour, minute: 0, addOneDay: converted.addOneDay, invalid: false, consumedRegexes: [hourOnly.pattern], anchorUTF16: hourOnly.range.location)
        }

        return nil
    }

    func convertHour(rawHour: Int, meridiem: String?) -> (hour: Int, addOneDay: Bool)? {
        if let meridiem {
            guard (1...12).contains(rawHour) else { return nil }
            switch meridiem {
            case "오전":
                return (rawHour == 12 ? 0 : rawHour, false)
            case "오후":
                return (rawHour == 12 ? 12 : rawHour + 12, false)
            case "밤":
                if rawHour == 12 {
                    return (0, true)
                }
                return (rawHour + 12, false)
            default:
                return nil
            }
        }

        guard (0...23).contains(rawHour) else { return nil }
        return (rawHour, false)
    }

    func resolveWeekday(weekday: Int, baseDate: Date, weekOffset: Int, forceFuture: Bool) -> Date? {
        let currentWeekStart = startOfWeek(for: baseDate)
        guard let weekBase = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeekStart) else { return nil }

        let weekStartWeekday = calendar.component(.weekday, from: weekBase)
        var delta = weekday - weekStartWeekday
        if delta < 0 { delta += 7 }

        guard var candidate = calendar.date(byAdding: .day, value: delta, to: weekBase) else { return nil }

        if forceFuture {
            let nowWeekday = calendar.component(.weekday, from: baseDate)
            if weekday < nowWeekday {
                candidate = calendar.date(byAdding: .day, value: 7, to: candidate) ?? candidate
            }
        }

        return candidate
    }

    func extractLocation(text: String, anchorUTF16: Int?) -> String? {
        let regex = try? NSRegularExpression(pattern: #"([가-힣A-Za-z0-9]+)에서"#)
        let ns = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        guard !matches.isEmpty else { return nil }

        if let anchorUTF16 {
            if let nearestAfter = matches.first(where: { $0.range.location >= anchorUTF16 }) {
                return ns.substring(with: nearestAfter.range(at: 1))
            }
        }

        if let first = matches.first {
            return ns.substring(with: first.range(at: 1))
        }
        return nil
    }

    func extractTitle(text: String, dateRegexes: [String], timeRegexes: [String], location: String?) -> String {
        var cleaned = text
        var patterns = dateRegexes
        patterns.append(contentsOf: timeRegexes)
        patterns.append(#"(오전|오후|밤)"#)

        for pattern in patterns {
            cleaned = cleaned.replacing(pattern: pattern, with: " ")
        }

        if let location, !location.isEmpty {
            cleaned = cleaned.replacingOccurrences(of: "\(location)에서", with: " ")
        }

        cleaned = cleaned.replacing(pattern: #"(에|에서|까지|쯤|경)"#, with: " ")
        cleaned = cleaned.replacing(pattern: #"\s+"#, with: " ")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    func weekdayKoreanToCalendar(_ token: String) -> Int? {
        switch token {
        case "일요일": return 1
        case "월요일": return 2
        case "화요일": return 3
        case "수요일": return 4
        case "목요일": return 5
        case "금요일": return 6
        case "토요일": return 7
        default: return nil
        }
    }

    func startOfMonth(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    func startOfWeek(for date: Date) -> Date {
        var cal = calendar
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: date)
        let shifted = (weekday - cal.firstWeekday + 7) % 7
        let dayStart = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: -shifted, to: dayStart) ?? dayStart
    }

    func makeValidDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let date = calendar.date(from: comps) else { return nil }
        let verify = calendar.dateComponents([.year, .month, .day], from: date)
        if verify.year == year, verify.month == month, verify.day == day {
            return date
        }
        return nil
    }

    func normalizeSpaces(_ text: String) -> String {
        text.replacing(pattern: #"\s+"#, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func firstMatch(_ pattern: String, in text: String) -> RegexMatch? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return RegexMatch(pattern: pattern, text: text, range: match.range, groups: (0..<match.numberOfRanges).map { match.range(at: $0) })
    }
}

private struct RegexMatch {
    let pattern: String
    let text: String
    let range: NSRange
    let groups: [NSRange]

    func group(_ index: Int) -> String? {
        guard groups.indices.contains(index), groups[index].location != NSNotFound else { return nil }
        return (text as NSString).substring(with: groups[index])
    }

    func int(_ index: Int) -> Int? {
        guard let str = group(index) else { return nil }
        return Int(str)
    }
}

private extension String {
    func replacing(pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(location: 0, length: (self as NSString).length)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }
}
