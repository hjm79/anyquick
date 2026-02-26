import Foundation

public struct ParsedSchedule: Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String?
    public let source: String

    public init(title: String, start: Date, end: Date, allDay: Bool, location: String?, source: String) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.source = source
    }
}

public struct ScheduleParseError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct KoreanScheduleParser {
    private let calendar: Calendar

    public init() {
        self.calendar = KoreanScheduleParser.defaultCalendar()
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func parse(_ input: String, baseDate: Date = Date(), defaultDurationMinutes: Int = 60) -> ParsedSchedule? {
        switch parseResult(input, baseDate: baseDate, defaultDurationMinutes: defaultDurationMinutes) {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }

    public func parseResult(_ input: String, baseDate: Date = Date(), defaultDurationMinutes: Int = 60) -> Result<ParsedSchedule, ScheduleParseError> {
        let scheduleString = input.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheduleString.isEmpty else {
            return .failure(ScheduleParseError("일정 문장이 비어 있습니다."))
        }

        guard let regex = try? NSRegularExpression(pattern: Self.matcherPattern) else {
            return .failure(ScheduleParseError("파서 정규식을 초기화하지 못했습니다."))
        }
        let ns = scheduleString as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard regex.firstMatch(in: scheduleString, range: range) != nil else {
            return .failure(ScheduleParseError("날짜/시간 패턴을 인식하지 못했습니다."))
        }

        guard let parsed = parseInternal(scheduleString, baseDate: baseDate, defaultDurationMinutes: defaultDurationMinutes) else {
            return .failure(ScheduleParseError("날짜/시간 계산에 실패했습니다. 입력값을 확인해 주세요."))
        }

        return .success(parsed)
    }
}

private extension KoreanScheduleParser {
    enum DateExpressionKind {
        case absoluteWithYear
        case absoluteMonthDay
        case monthModifier
        case weekday
        case dayModifier
    }

    static let dayModifierTokens = ["오늘", "내일", "모레"]
    static let weekdayTokens = ["일", "월", "화", "수", "목", "금", "토"]
    static let amTokens: Set<String> = ["새벽", "아침", "오전"]
    static let pmTokens: Set<String> = ["점심", "오후", "저녁", "밤"]

    static let matcherPattern = #"^((이달|이번달|담달|다음달|(내년|[0-9]{4}년){0,1} *[0-9]+월){0,1} *[0-9]+일+|오늘|내일|모레|(이번주|담주|다음주|다담주|다다음주){0,1} *([월화수목금토일](요일|욜)))( *(새벽|아침|점심|오전|오후|저녁|밤){0,1} *([0-9]+시|[0-9]+:[0-9]+) *([0-9]+분|반){0,1}){0,1}에{0,1}( *(.+?)에서){0,1} *"#

    static func defaultCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ko_KR")
        cal.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return cal
    }

    func parseInternal(_ input: String, baseDate: Date, defaultDurationMinutes: Int) -> ParsedSchedule? {
        let scheduleString = input.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheduleString.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: Self.matcherPattern) else { return nil }
        let ns = scheduleString as NSString
        let searchRange = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: scheduleString, range: searchRange) else { return nil }

        let now = baseDate
        let today = startOfDay(now)
        let durationMinutes = max(1, defaultDurationMinutes)

        var absoluteDate = group(match, in: scheduleString, at: 1)
        let weekModifierToken = group(match, in: scheduleString, at: 4)
        let weekdayToken = group(match, in: scheduleString, at: 5)
        let ampmToken = group(match, in: scheduleString, at: 8)
        let hourToken = group(match, in: scheduleString, at: 9)
        var minuteTokenString = group(match, in: scheduleString, at: 10) ?? "0"
        let place: String? = {
            let value = group(match, in: scheduleString, at: 12)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (value?.isEmpty == false) ? value : nil
        }()

        var year: Int?
        var month: Int?
        var day: Int?
        var date: Date?
        var dateExpressionKind: DateExpressionKind?

        var monthModifier: Int?
        var dayModifier: Int?

        if let absoluteDateValue = absoluteDate {
            if absoluteDateValue.contains("오늘") || absoluteDateValue.contains("내일") || absoluteDateValue.contains("모레") {
                dayModifier = Self.dayModifierTokens.firstIndex(of: absoluteDateValue)
            }

            if absoluteDateValue.contains("이달") || absoluteDateValue.contains("이번달") || absoluteDateValue.contains("담달") || absoluteDateValue.contains("다음달") {
                if absoluteDateValue.contains("이달") || absoluteDateValue.contains("이번달") {
                    monthModifier = 0
                }
                if absoluteDateValue.contains("담달") || absoluteDateValue.contains("다음달") {
                    monthModifier = 1
                }

                if let dayMatch = absoluteDateValue.firstMatch(#"([0-9]+)일"#, group: 1) {
                    day = Int(dayMatch)
                }
            }

            if let fullDate = absoluteDateValue.matchGroups(#"(내년|([0-9]{4})년) *([0-9]+)월 *([0-9]+)일"#) {
                dateExpressionKind = .absoluteWithYear
                if absoluteDateValue.contains("내년") {
                    year = calendar.component(.year, from: today) + 1
                }
                if let explicitYear = fullDate[2], !explicitYear.isEmpty {
                    year = Int(explicitYear)
                }
                if let parsedMonth = fullDate[3] {
                    month = Int(parsedMonth)
                }
                if let parsedDay = fullDate[4] {
                    day = Int(parsedDay)
                }
            }
        }

        if let abs = absoluteDate?.trimmingCharacters(in: .whitespacesAndNewlines), abs.range(of: #"^[0-9월일 ]+$"#, options: .regularExpression) != nil {
            absoluteDate = abs
        } else {
            absoluteDate = nil
        }

        var weekModifier: Int?
        if weekModifierToken == "이번주" {
            weekModifier = 0
        }
        if weekModifierToken == "담주" || weekModifierToken == "다음주" {
            weekModifier = 7
        }
        if weekModifierToken == "다담주" || weekModifierToken == "다다음주" {
            weekModifier = 14
        }

        var weekday: Int?
        if let weekdayToken {
            let normalized = weekdayToken.replacingOccurrences(of: #"^([월화수목금토일]).*"#, with: "$1", options: .regularExpression)
            if let index = Self.weekdayTokens.firstIndex(of: normalized) {
                weekday = index
            }
        }

        var hour: Int?
        if let hourToken {
            if let hourMinute = hourToken.matchGroups(#"^([0-9]+):([0-9]+)$"#) {
                hour = hourMinute[1].flatMap(Int.init)
                if let minuteDigits = hourMinute[2] {
                    minuteTokenString = "\(minuteDigits)분"
                }
            } else {
                let parsedHour = hourToken.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
                hour = Int(parsedHour)
            }
        }

        var ampm: String?
        if let ampmToken {
            if Self.amTokens.contains(ampmToken) {
                ampm = "am"
            }
            if Self.pmTokens.contains(ampmToken) {
                ampm = "pm"
            }
        }

        var minute: Int?
        if minuteTokenString == "반" {
            minute = 30
        } else {
            minute = Int(minuteTokenString.replacingOccurrences(of: "분", with: ""))
        }
        if minute == nil {
            minute = 0
        }

        if let absoluteDate, let absMonthDay = absoluteDate.matchGroups(#"(([0-9]+)월){0,1} *([0-9]+)일"#) {
            dateExpressionKind = .absoluteMonthDay
            year = calendar.component(.year, from: today)
            if let parsedMonth = absMonthDay[2], !parsedMonth.isEmpty {
                month = Int(parsedMonth)
            } else {
                month = calendar.component(.month, from: today)
            }
            day = absMonthDay[3].flatMap(Int.init)
        } else if let monthModifier, let day {
            dateExpressionKind = .monthModifier
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = 1
            guard let monthStart = calendar.date(from: comps),
                  let shiftedDate = calendar.date(byAdding: .month, value: monthModifier, to: monthStart) else {
                return nil
            }
            let shiftedYear = calendar.component(.year, from: shiftedDate)
            let shiftedMonth = calendar.component(.month, from: shiftedDate)

            guard isValidDayOfMonth(year: shiftedYear, month: shiftedMonth, day: day) else {
                return nil
            }

            date = makeDate(year: shiftedYear, month: shiftedMonth, day: day, hour: 0, minute: 0)
        } else if let weekday {
            dateExpressionKind = .weekday
            let normalizedWeekday = weekday == 0 ? 7 : weekday
            let currentWeekdayRaw = calendar.component(.weekday, from: today)
            let currentWeekday = currentWeekdayRaw == 1 ? 7 : currentWeekdayRaw - 1
            let offset = (weekModifier ?? 0) - currentWeekday + normalizedWeekday
            date = addDays(today, offset)
        } else if let dayModifier {
            dateExpressionKind = .dayModifier
            date = addDays(today, dayModifier)
        }

        if let date {
            year = calendar.component(.year, from: date)
            month = calendar.component(.month, from: date)
            day = calendar.component(.day, from: date)
        }

        if let month, !(1...12).contains(month) {
            return nil
        }

        if let day, day < 1 {
            return nil
        }

        if let year, let month, let day,
           !isValidDayOfMonth(year: year, month: month, day: day) {
            return nil
        }

        if let hour {
            if ampm != nil && !(1...12).contains(hour) {
                return nil
            }
            if ampm == nil && !(0...23).contains(hour) {
                return nil
            }
        }

        if let minute, !(0...59).contains(minute) {
            return nil
        }

        if let rawHour = hour {
            if ampm == "am" && rawHour == 12 {
                hour = 0
            } else if ampmToken == "밤" && rawHour == 12 {
                hour = 24
            } else if ampm == "pm" && rawHour < 12 {
                hour = rawHour + 12
            }
        } else {
            minute = nil
        }

        guard let year, let month, let day else {
            return nil
        }

        let title = remainingTitle(source: scheduleString, consumedRange: match.range)
        let hasTime = hour != nil && minute != nil

        guard var start = hasTime
            ? makeDate(year: year, month: month, day: day, hour: hour ?? 0, minute: minute ?? 0)
            : makeDate(year: year, month: month, day: day, hour: 0, minute: 0)
        else {
            return nil
        }

        var end: Date
        if hasTime {
            end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        } else {
            end = addDays(start, 1)
        }

        let comparisonNow = hasTime ? now : today
        if start < comparisonNow {
            if dateExpressionKind == .absoluteMonthDay {
                while start < comparisonNow {
                    start = addYears(start, 1)
                    end = addYears(end, 1)
                }
            } else if dateExpressionKind == .weekday && weekModifier == nil {
                start = addDays(start, 7)
                end = addDays(end, 7)
            }
        }

        return ParsedSchedule(
            title: title,
            start: start,
            end: end,
            allDay: !hasTime,
            location: place,
            source: scheduleString
        )
    }

    func group(_ match: NSTextCheckingResult, in text: String, at index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: range)
    }

    func remainingTitle(source: String, consumedRange: NSRange) -> String {
        let ns = source as NSString
        let tailStart = consumedRange.location + consumedRange.length
        let tailLength = max(0, ns.length - tailStart)
        let raw = ns.substring(with: NSRange(location: tailStart, length: tailLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? "새 일정" : raw
    }

    func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func addDays(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    func addYears(_ date: Date, _ years: Int) -> Date {
        calendar.date(byAdding: .year, value: years, to: date) ?? date
    }

    func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day

        if hour == 24 {
            comps.hour = 0
            comps.minute = minute
            comps.second = 0
            guard let base = calendar.date(from: comps) else { return nil }
            return calendar.date(byAdding: .day, value: 1, to: base)
        }

        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }

    func isValidDayOfMonth(year: Int, month: Int, day: Int) -> Bool {
        guard (1...12).contains(month), day >= 1 else { return false }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0

        guard let date = calendar.date(from: comps) else { return false }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        return verified.year == year && verified.month == month && verified.day == day
    }
}

private extension String {
    func firstMatch(_ pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: self, range: range),
              group < match.numberOfRanges else {
            return nil
        }
        let capture = match.range(at: group)
        guard capture.location != NSNotFound else { return nil }
        return ns.substring(with: capture)
    }

    func matchGroups(_ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let capture = match.range(at: index)
            guard capture.location != NSNotFound else { return nil }
            return ns.substring(with: capture)
        }
    }
}
