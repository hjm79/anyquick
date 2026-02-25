import Foundation

struct SmartParser {
    private let scheduleParser: KoreanScheduleParser
    private let mockContacts = ["엄마", "팀장님", "김철수", "여자친구"]

    init(scheduleParser: KoreanScheduleParser = KoreanScheduleParser()) {
        self.scheduleParser = scheduleParser
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
    func parseMessage(_ input: String) -> SmartIntent? {
        guard let name = mockContacts.first(where: { input.contains($0) }) else { return nil }

        let hasCurrentLocation = input.contains("현위치") || input.contains("내위치")

        var message = input
        message = message.replacingOccurrences(of: name, with: " ")
        message = message.replacingOccurrences(of: "현위치", with: " ")
        message = message.replacingOccurrences(of: "내위치", with: " ")
        message = cleanText(message)

        return .sendMessage(targetName: name, message: message, isCurrentLocation: hasCurrentLocation)
    }

    func parseNavigation(_ input: String) -> SmartIntent? {
        let keywords = ["내비", "안내", "길찾기", "카카오맵", "티맵"]
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
}
