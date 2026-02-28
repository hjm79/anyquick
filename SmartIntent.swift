import Foundation

enum SearchType: String, CaseIterable {
    case naver, youtube, netflix, tmdb, appstore, dictionary
    case dictionaryEnglish, dictionaryKorean, dictionaryHanja
    case google, shoppingNaver, coupang, aliexpress
    case chatgpt, gemini, claude, perplexity, grok
    case mapNaver, mapKakaoMap, mapKakaoNavi, mapTmap
}

struct CommandAlias: Codable, Identifiable, Equatable {
    let id: UUID
    var keyword: String
    var searchType: String

    init(keyword: String, searchType: String) {
        self.id = UUID()
        self.keyword = keyword
        self.searchType = searchType
    }
}

enum SmartIntent {
    case addSchedule(ParsedSchedule)
    case sendMessage(targetName: String, message: String, isCurrentLocation: Bool)
    case navigation(destination: String)
    case webSearch(query: String, type: SearchType)
    case unknown
}
