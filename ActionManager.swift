import Foundation
import UIKit
import Contacts
import CoreLocation
import MessageUI
import EventKit
import EventKitUI
import SafariServices

@MainActor
final class ActionManager: NSObject, ObservableObject {
    enum MessageChannel {
        case sms
        case appShare
    }

    enum ScheduleSaveDestination {
        case calendarEvent
        case reminder
    }

    enum LocationShareType {
        case kakao
        case naver
        case both
    }

    struct EventCalendarOption: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceTitle: String
    }

    @Published var actionNotice: String?

    private let contactStore = CNContactStore()
    private let eventStore = EKEventStore()
    private let userDefaults = UserDefaults.standard

    private var locationManager: CLLocationManager?
    private var locationAuthContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var noticeResetTask: Task<Void, Never>?

    private let preferredEventCalendarIdentifierKey = "preferredEventCalendarIdentifier"
    private let preferredReminderListIdentifierKey = "preferredReminderListIdentifier"
    private let defaultSearchEngineKey = "defaultSearchEngine"
    private let defaultAIServiceKey = "defaultAIService"
    private let searchHistoryKey = "searchHistory"
    private let commandAliasesKey = "commandAliases"
    private let preferAppForSearchKey = "preferAppForSearch"
    private let maxSearchHistoryCount = 10

    func preferAppForSearch() -> Bool {
        // 기본값: true (앱 우선)
        if userDefaults.object(forKey: preferAppForSearchKey) == nil { return true }
        return userDefaults.bool(forKey: preferAppForSearchKey)
    }

    func setPreferAppForSearch(_ value: Bool) {
        userDefaults.set(value, forKey: preferAppForSearchKey)
    }

    // MARK: Command Aliases

    func commandAliases() -> [CommandAlias] {
        guard let data = userDefaults.data(forKey: commandAliasesKey) else { return [] }
        return (try? JSONDecoder().decode([CommandAlias].self, from: data)) ?? []
    }

    func addCommandAlias(keyword: String, searchType: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, SearchType(rawValue: searchType) != nil else { return }

        var aliases = commandAliases()
        // 중복 키워드 방지
        aliases.removeAll { $0.keyword.lowercased() == trimmed.lowercased() }
        aliases.append(CommandAlias(keyword: trimmed, searchType: searchType))
        saveAliases(aliases)
    }

    func removeCommandAlias(id: UUID) {
        var aliases = commandAliases()
        aliases.removeAll { $0.id == id }
        saveAliases(aliases)
    }

    private func saveAliases(_ aliases: [CommandAlias]) {
        guard let data = try? JSONEncoder().encode(aliases) else { return }
        userDefaults.set(data, forKey: commandAliasesKey)
    }

    func execute(_ intent: SmartIntent) async {
        switch intent {
        case .addSchedule(let parsed):
            await executeSchedule(parsed, destination: .calendarEvent)
        case .sendMessage(let targetName, let message, let isCurrentLocation):
            await executeMessage(
                targetName: targetName,
                message: message,
                isCurrentLocation: isCurrentLocation,
                channel: .sms,
                locationShareType: .both
            )
        case .navigation:
            break // 내비게이션은 ViewModel에서 앱 선택 다이얼로그를 통해 openWebSearch로 처리
        case .webSearch(let query, let type):
            await openWebSearch(query: query, type: type)
        case .unknown:
            break
        }
    }

    func executeSchedule(_ parsed: ParsedSchedule, destination: ScheduleSaveDestination) async {
        switch destination {
        case .calendarEvent:
            await presentScheduleEditor(with: parsed)
        case .reminder:
            await saveReminder(with: parsed)
        }
    }

    func fetchWritableEventCalendars() async -> [EventCalendarOption] {
        let granted = await requestCalendarAccessIfNeeded()
        guard granted else { return [] }

        return eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { calendar in
                EventCalendarOption(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title
                )
            }
            .sorted { lhs, rhs in
                if lhs.sourceTitle == rhs.sourceTitle {
                    return lhs.title.localizedCompare(rhs.title) == .orderedAscending
                }
                return lhs.sourceTitle.localizedCompare(rhs.sourceTitle) == .orderedAscending
            }
    }

    func preferredEventCalendarIdentifier() -> String? {
        userDefaults.string(forKey: preferredEventCalendarIdentifierKey)
    }

    func setPreferredEventCalendarIdentifier(_ identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            userDefaults.removeObject(forKey: preferredEventCalendarIdentifierKey)
            return
        }
        userDefaults.set(identifier, forKey: preferredEventCalendarIdentifierKey)
    }

    func fetchWritableReminderLists() async -> [EventCalendarOption] {
        let granted = await requestReminderAccessIfNeeded()
        guard granted else { return [] }

        return eventStore.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { calendar in
                EventCalendarOption(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    sourceTitle: calendar.source.title
                )
            }
            .sorted { lhs, rhs in
                if lhs.sourceTitle == rhs.sourceTitle {
                    return lhs.title.localizedCompare(rhs.title) == .orderedAscending
                }
                return lhs.sourceTitle.localizedCompare(rhs.sourceTitle) == .orderedAscending
            }
    }

    func preferredReminderListIdentifier() -> String? {
        userDefaults.string(forKey: preferredReminderListIdentifierKey)
    }

    func setPreferredReminderListIdentifier(_ identifier: String?) {
        guard let identifier, !identifier.isEmpty else {
            userDefaults.removeObject(forKey: preferredReminderListIdentifierKey)
            return
        }
        userDefaults.set(identifier, forKey: preferredReminderListIdentifierKey)
    }

    // MARK: Default Search Engine

    func defaultSearchEngine() -> String? {
        userDefaults.string(forKey: defaultSearchEngineKey)
    }

    func setDefaultSearchEngine(_ rawValue: String?) {
        guard let rawValue, !rawValue.isEmpty else {
            userDefaults.removeObject(forKey: defaultSearchEngineKey)
            return
        }
        userDefaults.set(rawValue, forKey: defaultSearchEngineKey)
    }

    func defaultAIService() -> String? {
        userDefaults.string(forKey: defaultAIServiceKey)
    }

    func setDefaultAIService(_ rawValue: String?) {
        guard let rawValue, !rawValue.isEmpty else {
            userDefaults.removeObject(forKey: defaultAIServiceKey)
            return
        }
        userDefaults.set(rawValue, forKey: defaultAIServiceKey)
    }

    // MARK: Search History

    func searchHistory() -> [String] {
        userDefaults.stringArray(forKey: searchHistoryKey) ?? []
    }

    func addSearchHistory(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var history = searchHistory()
        history.removeAll { $0 == trimmed }
        history.insert(trimmed, at: 0)
        if history.count > maxSearchHistoryCount {
            history = Array(history.prefix(maxSearchHistoryCount))
        }
        userDefaults.set(history, forKey: searchHistoryKey)
    }

    func removeSearchHistory(at index: Int) {
        var history = searchHistory()
        guard index >= 0, index < history.count else { return }
        history.remove(at: index)
        userDefaults.set(history, forKey: searchHistoryKey)
    }

    func clearSearchHistory() {
        userDefaults.removeObject(forKey: searchHistoryKey)
    }

    func executeMessage(
        targetName: String,
        message: String,
        isCurrentLocation: Bool,
        channel: MessageChannel,
        locationShareType: LocationShareType = .both
    ) async {
        let trimmedTargetName = targetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient: String?
        if trimmedTargetName.isEmpty {
            recipient = nil
        } else {
            recipient = await findPhoneNumber(for: trimmedTargetName)
        }

        let body = await composeMessageBody(
            baseMessage: message,
            isCurrentLocation: isCurrentLocation,
            locationShareType: locationShareType
        )

        switch channel {
        case .sms:
            guard MFMessageComposeViewController.canSendText() else {
                showNotice("문자를 사용할 수 없어 앱 공유로 전환합니다.")
                presentShareSheet(text: body)
                return
            }
            presentMessageComposer(recipient: recipient, body: body)
        case .appShare:
            presentShareSheet(text: body)
        }
    }

    func fetchAllContactNames() async -> [String] {
        let granted = await requestContactsAccessIfNeeded()
        guard granted else { return [] }

        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactMiddleNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)

            var names = Set<String>()
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let middle = contact.middleName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let nickname = contact.nickname.trimmingCharacters(in: .whitespacesAndNewlines)

                    let compactFull = "\(family)\(middle)\(given)".trimmingCharacters(in: .whitespacesAndNewlines)
                    let spacedFull = [family, middle, given].filter { !$0.isEmpty }.joined(separator: " ")
                    let reversed = [given, family].filter { !$0.isEmpty }.joined(separator: " ")

                    for candidate in [compactFull, spacedFull, reversed, given, nickname] {
                        guard !candidate.isEmpty else { continue }
                        names.insert(candidate)
                        let noSpaces = candidate.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                        if !noSpaces.isEmpty {
                            names.insert(noSpaces)
                        }
                    }
                }
            } catch {
                return []
            }

            return names.sorted()
        }.value
    }
}

// MARK: - Message
private extension ActionManager {
    func presentMessageComposer(recipient: String?, body: String) {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.body = body

        if let recipient {
            composer.recipients = [recipient]
        }

        guard let presenter = topViewController() else { return }
        presenter.present(composer, animated: true)
    }

    func presentShareSheet(text: String) {
        guard let presenter = topViewController() else { return }

        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activity, animated: true)
        showNotice("보낼 앱을 선택하세요. (문자/카카오톡 등)")
    }

    func composeMessageBody(
        baseMessage: String,
        isCurrentLocation: Bool,
        locationShareType: LocationShareType
    ) async -> String {
        var body = baseMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            body = "메시지를 보냅니다."
        }

        guard isCurrentLocation else {
            return body
        }

        guard let location = await fetchCurrentLocation() else {
            showNotice("현재 위치를 가져오지 못해 텍스트만 전송합니다.")
            return body
        }

        let locationText = locationShareText(for: location, type: locationShareType)
        return body + "\n\n" + locationText
    }

    func locationShareText(for location: CLLocation, type: LocationShareType) -> String {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        let kakao = "https://map.kakao.com/link/map/현위치,\(lat),\(lng)"
        let naverWeb = makeNaverWebMapURL(lat: lat, lng: lng)
        let naverApp = makeNaverAppURL(lat: lat, lng: lng)
        let coordinate = String(format: "좌표: %.6f, %.6f", lat, lng)

        switch type {
        case .kakao:
            return "현위치(카카오맵): \(kakao)\n\(coordinate)"
        case .naver:
            return "현위치(네이버맵 앱): \(naverApp)\n현위치(네이버맵 웹): \(naverWeb)\n\(coordinate)"
        case .both:
            return "현위치(카카오맵): \(kakao)\n현위치(네이버맵 앱): \(naverApp)\n현위치(네이버맵 웹): \(naverWeb)\n\(coordinate)"
        }
    }

    func makeNaverWebMapURL(lat: Double, lng: Double) -> String {
        var components = URLComponents(string: "https://map.naver.com/v5/")
        components?.queryItems = [
            URLQueryItem(name: "c", value: "\(lng),\(lat),16,0,0,0,dh")
        ]
        return components?.url?.absoluteString ?? "https://map.naver.com/v5/?c=\(lng),\(lat),16,0,0,0,dh"
    }

    func makeNaverAppURL(lat: Double, lng: Double) -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.hjm.anyquick"
        var components = URLComponents()
        components.scheme = "nmap"
        components.host = "place"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.7f", lat)),
            URLQueryItem(name: "lng", value: String(format: "%.7f", lng)),
            URLQueryItem(name: "name", value: "현위치"),
            URLQueryItem(name: "appname", value: bundleID)
        ]

        if let urlString = components.string {
            return urlString
        }

        let encodedName = "현위치".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "현위치"
        return "nmap://place?lat=\(lat)&lng=\(lng)&name=\(encodedName)&appname=\(bundleID)"
    }

    func findPhoneNumber(for targetName: String) async -> String? {
        let granted = await requestContactsAccessIfNeeded()
        guard granted else { return nil }

        return await Task.detached(priority: .userInitiated) { () -> String? in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor
            ]

            let predicate = CNContact.predicateForContacts(matchingName: targetName)

            do {
                let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
                for contact in contacts {
                    if let mobile = contact.phoneNumbers.first(where: { $0.label == CNLabelPhoneNumberMobile }) {
                        return mobile.value.stringValue
                    }
                    if let first = contact.phoneNumbers.first {
                        return first.value.stringValue
                    }
                }
                return nil
            } catch {
                return nil
            }
        }.value
    }

    func requestContactsAccessIfNeeded() async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                contactStore.requestAccess(for: .contacts) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func fetchCurrentLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }

        let manager = locationManager ?? CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager = manager

        let authorized = await ensureLocationAuthorization(with: manager)
        guard authorized else { return nil }

        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func ensureLocationAuthorization(with manager: CLLocationManager) async -> Bool {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                self.locationAuthContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            return false
        }
    }
}

// MARK: - Schedule
private extension ActionManager {
    func presentScheduleEditor(with parsed: ParsedSchedule) async {
        let granted = await requestCalendarAccessIfNeeded()
        guard granted else {
            showNotice("캘린더 접근 권한이 필요합니다.")
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = parsed.title
        event.startDate = parsed.start
        event.endDate = parsed.end
        event.isAllDay = parsed.allDay
        event.location = parsed.location
        event.calendar = preferredEventCalendar() ?? eventStore.defaultCalendarForNewEvents

        let editor = EKEventEditViewController()
        editor.eventStore = eventStore
        editor.event = event
        editor.editViewDelegate = self

        guard let presenter = topViewController() else { return }
        presenter.present(editor, animated: true)
    }

    func saveReminder(with parsed: ParsedSchedule) async {
        let granted = await requestReminderAccessIfNeeded()
        guard granted else {
            showNotice("미리알림 접근 권한이 필요합니다.")
            return
        }

        guard let reminderCalendar = preferredReminderList()
            ?? eventStore.defaultCalendarForNewReminders() else {
            showNotice("사용 가능한 미리알림 목록이 없습니다.")
            return
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = reminderCalendar
        reminder.title = parsed.title

        var notes: [String] = []
        if let location = parsed.location, !location.isEmpty {
            notes.append("위치: \(location)")
        }
        if !parsed.source.isEmpty {
            notes.append("원본: \(parsed.source)")
        }
        if !notes.isEmpty {
            reminder.notes = notes.joined(separator: "\n")
        }

        let dueCalendar = Calendar.current
        reminder.dueDateComponents = dueCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: parsed.start
        )

        do {
            try eventStore.save(reminder, commit: true)
            showNotice("미리알림을 등록했습니다.")
        } catch {
            showNotice("미리알림 등록에 실패했습니다.")
        }
    }

    func preferredEventCalendar() -> EKCalendar? {
        guard let identifier = preferredEventCalendarIdentifier() else {
            return nil
        }
        return eventStore
            .calendars(for: .event)
            .first(where: { $0.calendarIdentifier == identifier && $0.allowsContentModifications })
    }

    func preferredReminderList() -> EKCalendar? {
        guard let identifier = preferredReminderListIdentifier() else {
            return nil
        }
        return eventStore
            .calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == identifier && $0.allowsContentModifications })
    }

    func requestCalendarAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func requestReminderAccessIfNeeded() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

// MARK: - Web Search
private extension ActionManager {
    func openWebSearch(query: String, type: SearchType) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return
        }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        let bundleID = Bundle.main.bundleIdentifier ?? "com.hjm.anyquick"

        let urlString: String
        let useApp = preferAppForSearch()

        switch type {
        case .naver:
            let webURL = URL(string: "https://m.search.naver.com/search.naver?sm=mtp_hty.top&where=m&query=\(encoded)")
            if useApp {
                let appURL = URL(string: "naversearchapp://search?query=\(encoded)")
                openURLWithFallback(primary: appURL, fallback: webURL)
            } else if let webURL {
                openInSafari(url: webURL)
            }
            showNotice("네이버 검색을 실행합니다.")
            return
        case .youtube:
            let appURL = URL(string: "youtube://www.youtube.com/results?search_query=\(encoded)")
            let webURL = URL(string: "https://www.youtube.com/results?search_query=\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("YouTube 검색을 실행합니다.")
            return
        case .netflix:
            let appURL = URL(string: "nflx://www.netflix.com/search?q=\(encoded)")
            let webURL = URL(string: "https://www.netflix.com/search?q=\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("Netflix 검색을 실행합니다.")
            return
        case .tmdb:
            urlString = "https://www.themoviedb.org/search?language=ko&query=\(encoded)"
        case .appstore:
            urlString = "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=\(encoded)"
        case .dictionary:
            urlString = "https://m.search.naver.com/search.naver?where=m_ldic&sm=mtb_jum&query=\(encoded)"
        case .dictionaryEnglish:
            urlString = "https://m.search.naver.com/search.naver?where=m_endic&sm=mtb_jum&query=\(encoded)"
        case .dictionaryKorean:
            urlString = "https://m.search.naver.com/search.naver?where=m_krdic&sm=mtb_jum&query=\(encoded)"
        case .dictionaryHanja:
            urlString = "https://m.search.naver.com/search.naver?where=m_chdic&sm=mtb_jum&query=\(encoded)"
        case .google:
            let webURL = URL(string: "https://www.google.com/search?q=\(encoded)")
            if useApp {
                openURLWithFallback(primary: webURL, fallback: nil)
            } else if let webURL {
                openInSafari(url: webURL)
            }
            showNotice("구글 검색을 실행합니다.")
            return
        case .shoppingNaver:
            let shoppingURLString = "https://msearch.shopping.naver.com/search/all?query=\(encoded)"
            if let encodedShoppingURL = shoppingURLString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let appURL = URL(string: "naversearchapp://inappbrowser?url=\(encodedShoppingURL)") {
                let webURL = URL(string: shoppingURLString)
                openURLWithFallback(primary: appURL, fallback: webURL)
            }
            showNotice("네이버 쇼핑 검색을 실행합니다.")
            return
        case .coupang:
            let appURL = URL(string: "coupang://search?q=\(encoded)")
            let webURL = URL(string: "https://www.coupang.com/np/search?q=\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("쿠팡 검색을 실행합니다.")
            return
        case .aliexpress:
            urlString = "https://www.aliexpress.com/wholesale?SearchText=\(encoded)"
        case .chatgpt:
            let webURL = URL(string: "https://chatgpt.com/?q=\(encoded)")
            let fallbackURL = URL(string: "https://chatgpt.com/")
            openURLWithFallback(primary: webURL, fallback: fallbackURL)
            showNotice("ChatGPT를 실행합니다.")
            return
        case .gemini:
            let webURL = URL(string: "https://gemini.google.com/app?q=\(encoded)")
            let fallbackURL = URL(string: "https://gemini.google.com/app")
            guard let webURL else {
                openURLWithFallback(primary: fallbackURL, fallback: nil)
                UIPasteboard.general.string = trimmed
                showNotice("Gemini 웹으로 연결합니다. 입력 텍스트를 클립보드에 복사했습니다.")
                return
            }

            // Gemini는 URL 프리필이 불안정해 클립보드 복사를 함께 제공한다.
            UIPasteboard.general.string = trimmed
            let openedInApp = await openURL(webURL, options: [.universalLinksOnly: true])
            if openedInApp {
                showNotice("Gemini 앱을 실행합니다. 입력 텍스트를 클립보드에 복사했습니다.")
            } else {
                openURLWithFallback(primary: webURL, fallback: fallbackURL)
                showNotice("Gemini 웹으로 연결합니다. 입력 텍스트를 클립보드에 복사했습니다.")
            }
            return
        case .claude:
            let webURL = URL(string: "https://claude.ai/new?q=\(encoded)")
            let fallbackURL = URL(string: "https://claude.ai/new")
            openURLWithFallback(primary: webURL, fallback: fallbackURL)
            showNotice("Claude를 실행합니다.")
            return
        case .perplexity:
            let webURL = URL(string: "https://www.perplexity.ai/search/new?q=\(encoded)")
            let fallbackURL = URL(string: "https://www.perplexity.ai/")
            if useApp {
                openURLWithFallback(primary: webURL, fallback: fallbackURL)
            } else if let webURL {
                openInSafari(url: webURL)
            }
            showNotice("Perplexity를 실행합니다.")
            return
        case .grok:
            let webURL = URL(string: "https://grok.com/?q=\(encoded)")
            let fallbackURL = URL(string: "https://grok.com/")
            openURLWithFallback(primary: webURL, fallback: fallbackURL)
            showNotice("Grok을 실행합니다.")
            return
        case .mapNaver:
            let appURL = URL(string: "nmap://search?query=\(encoded)&appname=\(bundleID)")
            let webURL = URL(string: "https://map.naver.com/v5/search/\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("네이버맵을 실행합니다.")
            return
        case .mapKakaoMap:
            let appURL = URL(string: "kakaomap://search?q=\(encoded)")
            let webURL = URL(string: "https://map.kakao.com/link/search/\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("카카오맵을 실행합니다.")
            return
        case .mapKakaoNavi:
            let appURL = URL(string: "kakaomap://route?ep=\(encoded)&by=CAR")
            let webURL = URL(string: "https://map.kakao.com/link/to/\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("카카오내비 길안내를 시작합니다.")
            return
        case .mapTmap:
            let appURL = URL(string: "tmap://search?name=\(encoded)")
            let webURL = URL(string: "http://maps.apple.com/?q=\(encoded)")
            openURLWithFallback(primary: appURL, fallback: webURL)
            showNotice("티맵 검색결과에서 목적지를 선택해 주세요.")
            return
        }

        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        showNotice("검색을 실행했습니다.")
    }

    func openURLWithFallback(primary: URL?, fallback: URL?) {
        guard let primary else {
            if let fallback {
                UIApplication.shared.open(fallback)
            }
            return
        }

        UIApplication.shared.open(primary, options: [:]) { success in
            guard !success, let fallback else { return }
            UIApplication.shared.open(fallback)
        }
    }

    func openInSafari(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = scene.windows.first?.rootViewController else {
            UIApplication.shared.open(url)
            return
        }
        let safariVC = SFSafariViewController(url: url)
        var presenter = rootVC
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        presenter.present(safariVC, animated: true)
    }
}

// MARK: - Presentation / URL
extension ActionManager {
    func showNotice(_ message: String) {
        actionNotice = message
        noticeResetTask?.cancel()
        noticeResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                actionNotice = nil
            }
        }
    }

    func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        guard let root = scenes
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            return nil
        }

        var top = root
        while true {
            if let presented = top.presentedViewController {
                top = presented
                continue
            }
            if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
                top = visible
                continue
            }
            if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
                top = selected
                continue
            }
            break
        }
        return top
    }

    func openURL(
        _ url: URL,
        options: [UIApplication.OpenExternalURLOptionsKey: Any] = [:]
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: options) { success in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension ActionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                locationAuthContinuation?.resume(returning: true)
                locationAuthContinuation = nil
            case .denied, .restricted:
                locationAuthContinuation?.resume(returning: false)
                locationAuthContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                locationAuthContinuation?.resume(returning: false)
                locationAuthContinuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            locationContinuation?.resume(returning: locations.last)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }
}

// MARK: - MFMessageComposeViewControllerDelegate
extension ActionManager: MFMessageComposeViewControllerDelegate {
    nonisolated func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - EKEventEditViewDelegate
extension ActionManager: EKEventEditViewDelegate {
    nonisolated func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        Task { @MainActor in
            controller.dismiss(animated: true)
        }
    }
}
