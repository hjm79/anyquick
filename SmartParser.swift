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

    /// 입력 전처리: 전각→반각, 반복공백 통일
    func normalizeInput(_ input: String) -> String {
        var s = input.precomposedStringWithCanonicalMapping
        s = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? s
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 일정 결과에 웹검색 오버라이드 키워드가 포함되어 있는지 확인
    private static let webSearchOverrideKeywords = ["날씨", "환율", "주가", "뉴스", "검색", "맛집"]

    func parse(input: String, baseDate: Date = Date()) -> SmartIntent {
        let raw = normalizeInput(input)
        guard !raw.isEmpty else { return .unknown }

        // Priority 1: Schedule (with web search override guard)
        if let schedule = scheduleParser.parse(raw, baseDate: baseDate) {
            let titleLower = schedule.title
            let hasWebOverride = Self.webSearchOverrideKeywords.contains(where: { titleLower.contains($0) })
            if !hasWebOverride {
                return .addSchedule(schedule)
            }
            // 웹검색 오버라이드: 일정 파서 결과를 무시하고 아래로 진행
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

        // Priority 5: Web Search / App Launch
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
        message = cleanForMessage(message)

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
        message = cleanForMessage(message)

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
        let hasKeyword = keywords.contains(where: { input.contains($0) })

        // "A에서 B" / "A부터 B" 패턴 감지 (키워드 없이도 인식)
        if let regex = try? NSRegularExpression(pattern: #"(.+?)(?:에서|부터)\s+(.+)"#),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
           let originRange = Range(match.range(at: 1), in: input),
           let destRange = Range(match.range(at: 2), in: input) {
            var origin = String(input[originRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            var destination = String(input[destRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            // 키워드 제거 (있을 경우)
            for keyword in keywords {
                origin = origin.replacingOccurrences(of: keyword, with: " ")
                destination = destination.replacingOccurrences(of: keyword, with: " ")
            }
            // "로", "까지" 접미사 제거
            destination = destination.replacingOccurrences(
                of: #"\s*(으?로|까지)\s*$"#, with: "", options: .regularExpression
            )
            origin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)

            if !origin.isEmpty && !destination.isEmpty {
                return .navigation(origin: origin, destination: destination)
            }
        }

        // 키워드 기반 단일 목적지 (기존 로직)
        guard hasKeyword else { return nil }

        var text = input
        for keyword in keywords {
            text = text.replacingOccurrences(of: keyword, with: " ")
        }
        text = cleanForNavigation(text)
        guard !text.isEmpty else { return nil }

        return .navigation(origin: nil, destination: text)
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
        // AI 트리거 — 어근 접두사 매칭 (오타/띄어쓰기/존댓말 자동 흡수)
        } else if ["알려", "물어", "요약해", "번역해", "정리해", "설명해", "분석해", "찾아"]
                    .contains(where: { input.contains($0) }) ||
                    input.contains("질문") {
            searchType = .chatgpt  // OmniViewModel에서 defaultAI로 치환
        } else {
            return nil
        }

        var query = input
        // 서비스 키워드 제거
        let serviceKeywords = [
            "유튜브", "넷플릭스", "앱스토어", "사전", "영화", "TMDB", "tmdb",
            "ChatGPT", "chatgpt", "GPT", "gpt", "체티지피티",
            "Gemini", "gemini", "제미나이", "제미니",
            "Claude", "claude", "클로드",
            "Perplexity", "perplexity", "퍼플렉시티",
            "Grok", "grok", "그록",
            "검색", "질문"
        ]
        for keyword in serviceKeywords {
            query = query.replacingOccurrences(of: keyword, with: " ")
        }
        // AI 트리거 어근 + 접미사 패턴 제거 (줘/봐/바/조/주세요 등 자동 흡수)
        let aiStems = ["알려", "물어", "요약해", "번역해", "정리해", "설명해", "분석해", "찾아"]
        for stem in aiStems {
            query = query.replacingOccurrences(
                of: stem + #"[^\s]*"#,
                with: " ",
                options: .regularExpression
            )
        }

        query = cleanForSearch(query)

        // 빈 쿼리 → 앱 열기 폴백
        guard !query.isEmpty else {
            return .openApp(type: searchType)
        }

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

    // MARK: - 인텐트별 전용 클리닝

    /// 메시지용: 수신자, 전송 동사, 채널 키워드 제거
    func cleanForMessage(_ text: String) -> String {
        var cleaned = text
        let messageTokens = [
            "에게", "한테", "께", "문자", "메시지", "해줘", "해 줘", "보내줘", "보내 줘",
            "보내기", "보내조", "좀", "바로", "해주세요", "해 주세요",
            "카톡", "카카오톡", "공유", "전송", "틀어줘", "틀어 줘"
        ]
        for token in messageTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: " ")
        }
        return normalizeSpaces(cleaned)
    }

    /// 네비게이션용: 네비 키워드만 제거, "에서" 등 일반 단어 유지
    func cleanForNavigation(_ text: String) -> String {
        var cleaned = text
        let navTokens = ["으로", "좀", "바로", "해줘", "해 줘"]
        for token in navTokens {
            cleaned = cleaned.replacingOccurrences(of: token, with: " ")
        }
        return normalizeSpaces(cleaned)
    }

    /// 웹검색용: 쿼리를 최대한 보존, 특수문자만 정리
    func cleanForSearch(_ text: String) -> String {
        normalizeSpaces(text)
    }

    /// 공통: 특수문자 제거 + 공백 정리
    private func normalizeSpaces(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: #"[.,!?~`'\"\(\)\[\]{}<>:;|\\\-_=+*&^%$#@]"#, with: " ", options: .regularExpression)
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
