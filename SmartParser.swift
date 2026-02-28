import Foundation

struct ContactSelectionContext {
    let keyword: String
    let candidates: [String]
    let message: String
    let isCurrentLocation: Bool
}

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

        // Priority 3: Location share shortcut (without contact)
        if let locationShareIntent = parseLocationShare(raw) {
            return locationShareIntent
        }

        // Priority 4: Navigation
        if let navIntent = parseNavigation(raw) {
            return navIntent
        }

        // Priority 5: Web Search
        if let searchIntent = parseWebSearch(raw) {
            return searchIntent
        }

        return .unknown
    }

    func contactSelectionContext(input: String) -> ContactSelectionContext? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        guard let keywordMatch = findKeywordBeforeRecipientParticle(in: raw) else { return nil }

        let normalizedKeyword = normalizeForLookup(keywordMatch.keyword)
        guard !normalizedKeyword.isEmpty else { return nil }

        let candidates = contacts
            .filter { !normalizeForLookup($0).isEmpty }
            .filter {
                let normalizedName = normalizeForLookup($0)
                return normalizedName.contains(normalizedKeyword) || normalizedKeyword.contains(normalizedName)
            }
            .sorted { lhs, rhs in
                rankContact(lhs, keyword: normalizedKeyword) < rankContact(rhs, keyword: normalizedKeyword)
            }

        guard !candidates.isEmpty else { return nil }

        var message = raw
        message.replaceSubrange(keywordMatch.fullRange, with: " ")
        let locationShareCommand = containsLocationShareCommand(in: raw)
        let hasCurrentLocation = containsCurrentLocationToken(in: raw) || locationShareCommand
        if locationShareCommand {
            message = stripLocationShareTokens(in: message)
        } else {
            message = stripCurrentLocationTokens(in: message)
        }
        message = cleanText(message)

        return ContactSelectionContext(
            keyword: keywordMatch.keyword,
            candidates: candidates,
            message: message,
            isCurrentLocation: hasCurrentLocation
        )
    }
}

private extension SmartParser {
    struct RecipientKeywordMatch {
        let keyword: String
        let fullRange: Range<String.Index>
    }

    struct ContactMatch {
        let name: String
        let range: Range<String.Index>
    }

    func parseMessage(_ input: String) -> SmartIntent? {
        guard let matched = findContactMatch(in: input) else { return nil }

        let locationShareCommand = containsLocationShareCommand(in: input)
        let hasCurrentLocation = containsCurrentLocationToken(in: input) || locationShareCommand

        var message = input
        message.replaceSubrange(matched.range, with: " ")
        if locationShareCommand {
            message = stripLocationShareTokens(in: message)
        } else {
            message = stripCurrentLocationTokens(in: message)
        }
        message = cleanText(message)

        return .sendMessage(targetName: matched.name, message: message, isCurrentLocation: hasCurrentLocation)
    }

    func parseLocationShare(_ input: String) -> SmartIntent? {
        guard containsLocationShareCommand(in: input) else { return nil }
        guard input.range(of: #"(에게|한테|께)"#, options: .regularExpression) == nil else { return nil }
        return .sendMessage(targetName: "", message: "", isCurrentLocation: true)
    }

    func parseNavigation(_ input: String) -> SmartIntent? {
        let keywords = [
            "카카오내비", "카카오네비", "카카오 내비", "카카오 네비",
            "네비게이션", "내비", "네비",
            "안내", "길찾기", "카카오맵", "카카오 맵", "티맵", "지도", "맵"
        ]
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
            // 검색어에서 "사전" 제거 후 남은 텍스트의 언어 감지
            let queryForDetect = input.replacingOccurrences(of: "사전", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            searchType = detectDictionaryType(for: queryForDetect)
        } else if input.contains("영화") || lowercased.contains("tmdb") {
            searchType = .tmdb
        } else if lowercased.contains("chatgpt") || lowercased.contains("gpt") || input.contains("체티지피티") {
            searchType = .chatgpt
        } else if lowercased.contains("gemini") || input.contains("제미나이") || input.contains("제미니") {
            searchType = .gemini
        } else if lowercased.contains("claude") || input.contains("클로드") {
            searchType = .claude
        } else if lowercased.contains("perplexity") || input.contains("퍼플렉시티") {
            searchType = .perplexity
        } else if lowercased.contains("grok") || input.contains("그록") {
            searchType = .grok
        } else if input.contains("알려줘") ||
                    input.contains("알려 줘") ||
                    input.contains("물어봐") ||
                    input.contains("물어 봐") ||
                    input.contains("질문") {
            searchType = .chatgpt
        } else {
            return nil
        }

        var query = input
        let triggerKeywords = [
            "유튜브", "넷플릭스", "앱스토어", "사전", "영화", "TMDB", "tmdb",
            "ChatGPT", "chatgpt", "GPT", "gpt", "체티지피티",
            "Gemini", "gemini", "제미나이", "제미니",
            "Claude", "claude", "클로드",
            "Perplexity", "perplexity", "퍼플렉시티",
            "Grok", "grok", "그록",
            "검색", "찾아줘", "찾아 줘", "알려줘", "알려 줘",
            "물어봐", "물어 봐", "질문"
        ]
        for keyword in triggerKeywords {
            query = query.replacingOccurrences(of: keyword, with: " ")
        }

        query = cleanText(query)
        guard !query.isEmpty else { return nil }

        return .webSearch(query: query, type: searchType)
    }

    /// 검색어의 주요 문자 타입을 감지하여 적절한 사전 타입 반환
    private func detectDictionaryType(for query: String) -> SearchType {
        guard !query.isEmpty else { return .dictionaryKorean }

        var englishCount = 0
        var hanjaCount = 0
        var koreanCount = 0

        for scalar in query.unicodeScalars {
            if (scalar.value >= 0x41 && scalar.value <= 0x5A) ||
               (scalar.value >= 0x61 && scalar.value <= 0x7A) {
                englishCount += 1
            } else if scalar.value >= 0x4E00 && scalar.value <= 0x9FFF {
                hanjaCount += 1
            } else if scalar.value >= 0xAC00 && scalar.value <= 0xD7AF {
                koreanCount += 1
            }
        }

        if hanjaCount > 0 { return .dictionaryHanja }
        if englishCount > koreanCount { return .dictionaryEnglish }
        return .dictionaryKorean
    }

    func cleanText(_ text: String) -> String {
        var cleaned = text

        let removeTokens = [
            "에게", "한테", "문자", "메시지", "해줘", "해 줘", "보내줘", "보내 줘",
            "검색", "알려줘", "알려 줘", "으로", "에서", "틀어줘", "틀어 줘",
            "좀", "바로", "해주세요", "해 주세요", "카톡", "카카오톡", "공유", "전송"
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
            return ContactMatch(name: name, range: swiftRange)
        }

        return nil
    }

    func findKeywordBeforeRecipientParticle(in input: String) -> RecipientKeywordMatch? {
        let nsRange = NSRange(input.startIndex..<input.endIndex, in: input)
        let pattern = #"([가-힣A-Za-z0-9]+)\s*(에게|한테|께)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: input, options: [], range: nsRange),
              let keywordRange = Range(match.range(at: 1), in: input),
              let fullRange = Range(match.range(at: 0), in: input) else {
            return nil
        }

        let keyword = String(input[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return nil }
        return RecipientKeywordMatch(keyword: keyword, fullRange: fullRange)
    }

    func containsCurrentLocationToken(in text: String) -> Bool {
        text.range(of: #"(현\s*위치|내\s*위치|현재\s*위치|현위치|내위치)"#, options: .regularExpression) != nil
    }

    func containsLocationShareCommand(in text: String) -> Bool {
        let hasLocationToken = text.range(
            of: #"(현\s*위치|내\s*위치|현재\s*위치|현위치|내위치|위치)"#,
            options: .regularExpression
        ) != nil
        guard hasLocationToken else { return false }

        let hasChannelToken = text.range(
            of: #"(카톡|카카오톡|문자|메시지)"#,
            options: .regularExpression
        ) != nil
        guard hasChannelToken else { return false }

        let hasShareVerb = text.range(
            of: #"(보내|공유|전송)"#,
            options: .regularExpression
        ) != nil
        return hasShareVerb
    }

    func stripCurrentLocationTokens(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(현\s*위치|내\s*위치|현재\s*위치|현위치|내위치)"#,
            with: " ",
            options: .regularExpression
        )
    }

    func stripLocationShareTokens(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(현\s*위치|내\s*위치|현재\s*위치|현위치|내위치|위치)"#,
            with: " ",
            options: .regularExpression
        )
    }

    func rankContact(_ name: String, keyword: String) -> (Int, Int, String) {
        let normalized = normalizeForLookup(name)
        let exact = normalized == keyword ? 0 : 1
        let prefix = normalized.hasPrefix(keyword) ? 0 : 1
        let lengthDiff = abs(normalized.count - keyword.count)
        return (exact + prefix, lengthDiff, normalized)
    }

    func normalizeForLookup(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func normalizeContacts(_ names: [String]) -> [String] {
        var set = Set<String>()

        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            set.insert(trimmed)
        }

        return set.sorted { $0.count > $1.count }
    }
}
