import Foundation

final class SmartParser {
    private let scheduleParser: KoreanScheduleParser
    private var contactPool: [String]

    var contacts: [String] {
        get { contactPool }
        set { contactPool = Self.normalizeContacts(newValue) }
    }

    init(scheduleParser: KoreanScheduleParser = KoreanScheduleParser(), contacts: [String] = []) {
        self.scheduleParser = scheduleParser
        self.contactPool = Self.normalizeContacts(contacts)
    }

    func parse(input: String, baseDate: Date = Date()) -> SmartIntent {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .unknown }

        // Priority 1: Schedule
        if let schedule = scheduleParser.parse(raw, baseDate: baseDate) {
            return .addSchedule(schedule)
        }

        // Priority 2: Message
        if let messageIntent = parseMessage(raw) {
            return messageIntent
        }

        // Priority 3: Navigation
        if let navIntent = parseNavigation(raw) {
            return navIntent
        }

        // Priority 4: Web Search
        if let searchIntent = parseWebSearch(raw) {
            return searchIntent
        }

        return .unknown
    }
}

private extension SmartParser {
    struct ContactMatch {
        let name: String
        let range: Range<String.Index>
    }

    func parseMessage(_ input: String) -> SmartIntent? {
        guard let matched = findContactMatch(in: input) else { return nil }

        let hasCurrentLocation = input.contains("현위치") || input.contains("내위치")

        var message = input
        message.replaceSubrange(matched.range, with: " ")
        message = message.replacingOccurrences(of: "현위치", with: " ")
        message = message.replacingOccurrences(of: "내위치", with: " ")
        message = cleanText(message)

        return .sendMessage(targetName: matched.name, message: message, isCurrentLocation: hasCurrentLocation)
    }

    func parseNavigation(_ input: String) -> SmartIntent? {
        let keywords = ["내비", "네비", "네비게이션", "안내", "길찾기", "카카오맵", "티맵", "지도", "맵"]
        guard keywords.contains(where: { input.contains($0) }) else { return nil }

        var destination = input
        for keyword in keywords {
            destination = destination.replacingOccurrences(of: keyword, with: " ")
        }
        destination = cleanText(destination)
        guard !destination.isEmpty else { return nil }

        return .navigation(destination: destination)
    }

    func parseWebSearch(_ input: String) -> SmartIntent? {
        let lowercased = input.lowercased()
        let searchType: SearchType

        if input.contains("유튜브") {
            searchType = .youtube
        } else if input.contains("넷플릭스") {
            searchType = .netflix
        } else if input.contains("앱스토어") {
            searchType = .appstore
        } else if input.contains("사전") {
            searchType = .dictionary
        } else if input.contains("영화") || lowercased.contains("tmdb") {
            searchType = .tmdb
        } else if input.contains("검색") ||
                    input.contains("찾아줘") ||
                    input.contains("찾아 줘") ||
                    input.contains("알려줘") ||
                    input.contains("알려 줘") {
            searchType = .naver
        } else {
            return nil
        }

        var query = input
        let triggerKeywords = ["유튜브", "넷플릭스", "앱스토어", "사전", "영화", "TMDB", "tmdb", "검색", "찾아줘", "찾아 줘", "알려줘", "알려 줘"]
        for keyword in triggerKeywords {
            query = query.replacingOccurrences(of: keyword, with: " ")
        }

        query = cleanText(query)
        guard !query.isEmpty else { return nil }

        return .webSearch(query: query, type: searchType)
    }

    func cleanText(_ text: String) -> String {
        var cleaned = text

        let removeTokens = [
            "에게", "한테", "문자", "메시지", "해줘", "해 줘", "보내줘", "보내 줘",
            "검색", "알려줘", "알려 줘", "으로", "에서", "틀어줘", "틀어 줘",
            "좀", "바로", "해주세요", "해 주세요"
        ]

        for token in removeTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: " ")
        }

        cleaned = cleaned.replacingOccurrences(of: #"[.,!?~`'\"\(\)\[\]{}<>:;|/\\\-_=+*&^%$#@]"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func findContactMatch(in input: String) -> ContactMatch? {
        guard !contacts.isEmpty else { return nil }
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let particlePattern = "(?:에게|한테|께|님|씨|은|는|이|가|을|를|와|과|랑|하고|도|에서|으로|로|께서|에게서|한테서|한테로|에게로)"

        for name in contacts.sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let pattern = "(^|[\\s\\p{P}])(\(escaped))(?=$|[\\s\\p{P}]|\(particlePattern))"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            guard let match = regex.firstMatch(in: input, options: [], range: nsRange) else { continue }
            let nameRange = match.range(at: 2)
            guard let swiftRange = Range(nameRange, in: input) else { continue }
            let matchedText = String(input[swiftRange])
            return ContactMatch(name: matchedText, range: swiftRange)
        }

        return nil
    }

    static func normalizeContacts(_ names: [String]) -> [String] {
        var set = Set<String>()

        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            set.insert(trimmed)

            let noSpaces = trimmed.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            if !noSpaces.isEmpty {
                set.insert(noSpaces)
            }
        }

        return set.sorted { $0.count > $1.count }
    }
}
