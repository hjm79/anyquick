import Foundation

enum SearchType {
    case naver, youtube, netflix, tmdb, appstore, dictionary
}

enum SmartIntent {
    case addSchedule(ParsedSchedule)
    case sendMessage(targetName: String, message: String, isCurrentLocation: Bool)
    case navigation(destination: String)
    case webSearch(query: String, type: SearchType)
    case unknown
}
