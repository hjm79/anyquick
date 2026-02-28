import SwiftUI
import Combine
import UIKit
import Speech
import AVFoundation

@MainActor
final class OmniViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var predictedIntent: SmartIntent = .unknown
    @Published var actionNotice: String?
    @Published var contactSelectionPreview: [String] = []
    @Published var contactSelectionKeyword: String = ""
    @Published var contactPickerCandidates: [String] = []
    @Published var isContactPickerPresented: Bool = false
    @Published var isMessageChannelSheetPresented: Bool = false
    @Published var pendingHasEmail: Bool = false
    @Published var pendingMessageTargetLabel: String = ""
    @Published var isScheduleDestinationSheetPresented: Bool = false
    @Published var pendingScheduleTitle: String = ""
    @Published var isNavigationAppSheetPresented: Bool = false
    @Published var pendingNavigationDestination: String = ""
    @Published var pendingNavigationOrigin: String? = nil
    @Published var isWebSearchSheetPresented: Bool = false
    @Published var isAIAppSheetPresented: Bool = false
    @Published var pendingAIQuery: String = ""
    @Published var eventCalendarOptions: [ActionManager.EventCalendarOption] = []
    @Published var selectedEventCalendarIdentifier: String? = nil
    @Published var reminderListOptions: [ActionManager.EventCalendarOption] = []
    @Published var selectedReminderListIdentifier: String? = nil
    @Published var defaultSearchEngineRawValue: String? = nil
    @Published var defaultAIServiceRawValue: String? = nil
    @Published var searchHistory: [String] = []
    @Published var commandAliases: [CommandAlias] = []
    @Published var appShortcuts: [AppShortcut] = []
    @Published var preferAppForSearch: Bool = true
    @Published var isRecording: Bool = false

    private let smartParser: SmartParser
    private let actionManager: ActionManager
    private var cancellables = Set<AnyCancellable>()
    private var pendingMessageTarget: String = ""
    private var pendingMessageBody: String = ""
    private var pendingCurrentLocationFlag: Bool = false
    private var pendingSchedule: ParsedSchedule?
    private var manualNoticeResetTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    init(smartParser: SmartParser = SmartParser(), actionManager: ActionManager? = nil) {
        self.smartParser = smartParser
        let am = actionManager ?? ActionManager()
        self.actionManager = am

        // 앱 시작 시 바로 로딩 (설정 시트 열기 전에도 동작하도록)
        self.commandAliases = am.commandAliases()
        self.defaultSearchEngineRawValue = am.defaultSearchEngine()
        self.defaultAIServiceRawValue = am.defaultAIService()
        self.searchHistory = am.searchHistory()
        self.preferAppForSearch = am.preferAppForSearch()

        $inputText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                let parsed = self.smartParser.parse(input: text)
                let contactContext = self.smartParser.contactSelectionContext(input: text)
                withAnimation(.spring()) {
                    self.predictedIntent = parsed
                    if case .unknown = parsed {
                        self.contactSelectionPreview = Array((contactContext?.candidates ?? []).prefix(3))
                        self.contactSelectionKeyword = contactContext?.keyword ?? ""
                    } else {
                        self.contactSelectionPreview = []
                        self.contactSelectionKeyword = ""
                    }
                }
            }
            .store(in: &cancellables)

        self.actionManager.$actionNotice
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.actionNotice = message
                }
            }
            .store(in: &cancellables)

        Task { [weak self] in
            guard let self else { return }
            await self.refreshContacts()
        }
    }

    func executePredictedIntent() {
        // ① 별칭 매칭 (파서 이전에 실행)
        if let (alias, query) = matchAlias(inputText) {
            guard let type = SearchType(rawValue: alias.searchType) else { return }
            actionManager.addSearchHistory(query)
            searchHistory = actionManager.searchHistory()
            Task {
                await actionManager.execute(.webSearch(query: query, type: type))
                inputText = ""
            }
            return
        }

        // ② 기존 자연어 파서 로직
        if case .unknown = predictedIntent, prepareContactSelectionIfNeeded() {
            return
        }

        if case .addSchedule(let parsed) = predictedIntent {
            prepareScheduleDestinationSelection(parsed)
            return
        }

        if case .sendMessage(let targetName, let message, let isCurrentLocation) = predictedIntent {
            let raw = inputText
            let phoneKeywords = ["전화해", "전화 해", "전화걸", "전화 걸", "전화줘", "전화 줘", "전화하", "통화"]
            let emailKeywords = ["이메일", "메일 보내", "메일보내"]

            if phoneKeywords.contains(where: { raw.contains($0) }) {
                // "전화" 키워드 → 바로 전화 실행
                Task {
                    await actionManager.executeMessage(
                        targetName: targetName,
                        message: "",
                        isCurrentLocation: false,
                        channel: .phone
                    )
                    inputText = ""
                }
            } else if emailKeywords.contains(where: { raw.contains($0) }) {
                // "이메일" 키워드 → 바로 이메일 실행
                Task {
                    await actionManager.executeMessage(
                        targetName: targetName,
                        message: message,
                        isCurrentLocation: false,
                        channel: .email
                    )
                    inputText = ""
                }
            } else {
                // 일반 → 채널 선택 시트
                prepareMessageChannelSelection(
                    targetName: targetName,
                    message: message,
                    includeCurrentLocation: isCurrentLocation
                )
            }
            return
        }

        if case .navigation(let origin, let destination) = predictedIntent {
            prepareNavigationAppSelection(origin: origin, destination: destination)
            return
        }

        // AI 트리거 키워드(알려줘/물어봐/질문)로 파싱된 경우에만 기본 AI로 대체
        // 명시 AI 키워드(chatgpt, grok 등)는 그대로 실행
        if case .webSearch(let query, let type) = predictedIntent, isAISearchType(type) {
            let isFromTriggerKeyword = isAITriggerInput(inputText)
            if isFromTriggerKeyword, let raw = defaultAIServiceRawValue,
               let engine = SearchType(rawValue: raw) {
                actionManager.addSearchHistory(query)
                searchHistory = actionManager.searchHistory()
                Task {
                    await actionManager.execute(.webSearch(query: query, type: engine))
                    inputText = ""
                }
            } else if isFromTriggerKeyword {
                pendingAIQuery = query
                isAIAppSheetPresented = true
            } else {
                // 명시 AI 키워드 (grok, claude 등) → 해당 서비스로 바로 실행
                actionManager.addSearchHistory(query)
                searchHistory = actionManager.searchHistory()
                Task {
                    await actionManager.execute(.webSearch(query: query, type: type))
                    inputText = ""
                }
            }
            return
        }

        if case .unknown = predictedIntent {
            let cleaned = cleanSearchQuery(inputText)
            guard !cleaned.isEmpty else { return }

            // 기본 검색 엔진이 설정되어 있으면 바로 검색 실행
            if let raw = defaultSearchEngineRawValue,
               let engine = SearchType(rawValue: raw) {
                actionManager.addSearchHistory(cleaned)
                searchHistory = actionManager.searchHistory()
                Task {
                    await actionManager.execute(.webSearch(query: cleaned, type: engine))
                    inputText = ""
                }
            } else {
                isWebSearchSheetPresented = true
            }
            return
        }

        Task {
            await actionManager.execute(predictedIntent)
            inputText = ""
        }
    }

    func executeManualSearch(type: SearchType) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        actionManager.addSearchHistory(trimmed)
        searchHistory = actionManager.searchHistory()

        // 지도 숏컷: "A에서 B" 패턴 감지 → route navigation
        if [.mapNaver, .mapKakaoMap, .mapKakaoNavi, .mapTmap].contains(type),
           let parsed = parseRoutePattern(trimmed) {
            Task {
                await actionManager.openRouteNavigation(
                    origin: parsed.origin,
                    destination: parsed.destination,
                    type: type
                )
                inputText = ""
            }
            return
        }

        Task {
            await actionManager.execute(.webSearch(query: trimmed, type: type))
            inputText = ""
        }
    }

    /// "A에서 B" / "A부터 B" 패턴을 감지하여 출발지/목적지 분리
    private func parseRoutePattern(_ input: String) -> (origin: String, destination: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"(.+?)(?:에서|부터)\s+(.+)"#),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let originRange = Range(match.range(at: 1), in: input),
              let destRange = Range(match.range(at: 2), in: input) else {
            return nil
        }
        let origin = String(input[originRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        var destination = String(input[destRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // "로", "까지" 접미사 제거
        destination = destination.replacingOccurrences(
            of: #"\s*(으?로|까지)\s*$"#, with: "", options: .regularExpression
        )
        guard !origin.isEmpty, !destination.isEmpty else { return nil }
        return (origin, destination)
    }

    /// 경로 숏컷 버튼: 입력 텍스트를 출발지/목적지로 분리하여 route navigation 실행
    func executeRouteShortcut(type: SearchType) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        actionManager.addSearchHistory(trimmed)
        searchHistory = actionManager.searchHistory()

        // "에서/부터" 패턴 우선
        if let parsed = parseRoutePattern(trimmed) {
            Task {
                await actionManager.openRouteNavigation(
                    origin: parsed.origin,
                    destination: parsed.destination,
                    type: type
                )
                inputText = ""
            }
            return
        }

        // 공백 기반 분리: 마지막 공백 기준 (앞=출발지, 뒤=목적지)
        let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let origin = parts.dropLast().joined(separator: " ")
            let destination = parts.last!
            Task {
                await actionManager.openRouteNavigation(
                    origin: origin,
                    destination: destination,
                    type: type
                )
                inputText = ""
            }
        }
    }

    func executeReminderShortcut() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parsedIntent = smartParser.parse(input: trimmed)
        guard case .addSchedule(let parsed) = parsedIntent else {
            showManualNotice("일정 문장을 입력하면 미리알림으로 등록할 수 있습니다.")
            return
        }

        Task {
            await actionManager.executeSchedule(parsed, destination: .reminder)
            inputText = ""
        }
    }

    func pasteFromClipboard() {
        if let clipboard = UIPasteboard.general.string {
            inputText = clipboard
        }
    }

    func refreshContacts() async {
        let names = await actionManager.fetchAllContactNames()
        smartParser.contacts = names
    }

    func selectContactCandidate(_ name: String) {
        isContactPickerPresented = false
        prepareMessageChannelSelection(
            targetName: name,
            message: pendingMessageBody,
            includeCurrentLocation: pendingCurrentLocationFlag
        )
    }

    func cancelContactSelection() {
        isContactPickerPresented = false
    }

    func sendPendingMessageAsSMS() {
        executePendingMessage(channel: .sms)
    }

    func sendPendingMessageAsAppShare() {
        executePendingMessage(channel: .appShare)
    }

    func sendPendingMessageAsPhone() {
        executePendingMessage(channel: .phone)
    }

    func sendPendingMessageAsEmail() {
        executePendingMessage(channel: .email)
    }

    func cancelPendingMessageSelection() {
        isMessageChannelSheetPresented = false
    }

    func registerPendingScheduleAsCalendarEvent() {
        executePendingSchedule(destination: .calendarEvent)
    }

    func registerPendingScheduleAsReminder() {
        executePendingSchedule(destination: .reminder)
    }

    func cancelPendingScheduleSelection() {
        isScheduleDestinationSheetPresented = false
        pendingSchedule = nil
        pendingScheduleTitle = ""
    }

    func navigateWithKakaoMap() {
        executePendingNavigation(type: .mapKakaoMap)
    }

    func navigateWithKakaoNavi() {
        executePendingNavigation(type: .mapKakaoNavi)
    }

    func navigateWithTmap() {
        executePendingNavigation(type: .mapTmap)
    }

    func navigateWithNaverMap() {
        executePendingNavigation(type: .mapNaver)
    }

    func cancelNavigationAppSelection() {
        isNavigationAppSheetPresented = false
        pendingNavigationDestination = ""
        pendingNavigationOrigin = nil
    }

    func searchWithNaver() {
        executeWebSearch(type: .naver)
    }

    func searchWithGoogle() {
        executeWebSearch(type: .google)
    }

    func searchWithYouTube() {
        executeWebSearch(type: .youtube)
    }

    func searchWithAppStore() {
        executeWebSearch(type: .appstore)
    }

    func searchWithChatGPT() {
        executeWebSearch(type: .chatgpt)
    }

    func searchWithPerplexity() {
        executeWebSearch(type: .perplexity)
    }

    func cancelWebSearchSelection() {
        isWebSearchSheetPresented = false
    }

    // MARK: AI App Selection

    func aiWithChatGPT() {
        executePendingAI(type: .chatgpt)
    }

    func aiWithGemini() {
        executePendingAI(type: .gemini)
    }

    func aiWithClaude() {
        executePendingAI(type: .claude)
    }

    func aiWithPerplexity() {
        executePendingAI(type: .perplexity)
    }

    func aiWithGrok() {
        executePendingAI(type: .grok)
    }

    func cancelAIAppSelection() {
        isAIAppSheetPresented = false
        pendingAIQuery = ""
    }

    private func executePendingAI(type: SearchType) {
        let query = pendingAIQuery
        isAIAppSheetPresented = false
        pendingAIQuery = ""
        guard !query.isEmpty else { return }

        actionManager.addSearchHistory(query)
        searchHistory = actionManager.searchHistory()

        Task {
            await actionManager.execute(.webSearch(query: query, type: type))
            inputText = ""
        }
    }

    private func isAISearchType(_ type: SearchType) -> Bool {
        [.chatgpt, .gemini, .claude, .perplexity, .grok].contains(type)
    }

    /// AI 트리거 키워드(알려줘/물어봐/질문)만으로 AI가 선택된 경우인지 확인
    /// 명시 AI 키워드(chatgpt, grok 등)가 함께 있으면 false (명시가 우선)
    private func isAITriggerInput(_ input: String) -> Bool {
        // 어근 접두사 매칭 — 오타/띄어쓰기/존댓말 자동 흡수
        let aiStems = ["알려", "물어", "요약해", "번역해", "정리해", "설명해", "분석해", "찾아"]
        let hasTrigger = aiStems.contains { input.contains($0) } || input.contains("질문")
        guard hasTrigger else { return false }

        // 명시 AI 키워드가 있으면 트리거가 아닌 명시 입력
        let lowered = input.lowercased()
        let explicitKeywords = [
            "chatgpt", "gpt", "체티지피티",
            "gemini", "제미나이", "제미니",
            "claude", "클로드",
            "perplexity", "퍼플렉시티",
            "grok", "그록"
        ]
        let hasExplicit = explicitKeywords.contains { lowered.contains($0) }
        return !hasExplicit
    }

    private func executeWebSearch(type: SearchType) {
        let cleaned = cleanSearchQuery(inputText)
        isWebSearchSheetPresented = false
        guard !cleaned.isEmpty else { return }

        actionManager.addSearchHistory(cleaned)
        searchHistory = actionManager.searchHistory()

        Task {
            await actionManager.execute(.webSearch(query: cleaned, type: type))
            inputText = ""
        }
    }

    static let searchCommandKeywords = [
        "검색", "찾아줘", "찾아 줘"
    ]

    func cleanSearchQuery(_ input: String) -> String {
        var query = input
        for keyword in Self.searchCommandKeywords {
            query = query.replacingOccurrences(of: keyword, with: " ")
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedInputText: String {
        cleanSearchQuery(inputText)
    }

    func updatePreferredEventCalendar(identifier: String?) {
        selectedEventCalendarIdentifier = identifier
        actionManager.setPreferredEventCalendarIdentifier(identifier)
    }

    func updatePreferredReminderList(identifier: String?) {
        selectedReminderListIdentifier = identifier
        actionManager.setPreferredReminderListIdentifier(identifier)
    }

    func updateDefaultSearchEngine(_ rawValue: String?) {
        defaultSearchEngineRawValue = rawValue
        actionManager.setDefaultSearchEngine(rawValue)
    }

    func updateDefaultAIService(_ rawValue: String?) {
        defaultAIServiceRawValue = rawValue
        actionManager.setDefaultAIService(rawValue)
    }

    func loadSettings() async {
        // Calendar + Reminder settings
        let options = await actionManager.fetchWritableEventCalendars()
        eventCalendarOptions = options

        let preferred = actionManager.preferredEventCalendarIdentifier()
        if let preferred, options.contains(where: { $0.id == preferred }) {
            selectedEventCalendarIdentifier = preferred
        } else {
            selectedEventCalendarIdentifier = nil
            if preferred != nil {
                actionManager.setPreferredEventCalendarIdentifier(nil)
            }
        }

        let reminderOptions = await actionManager.fetchWritableReminderLists()
        reminderListOptions = reminderOptions

        let preferredReminder = actionManager.preferredReminderListIdentifier()
        if let preferredReminder, reminderOptions.contains(where: { $0.id == preferredReminder }) {
            selectedReminderListIdentifier = preferredReminder
        } else {
            selectedReminderListIdentifier = nil
            if preferredReminder != nil {
                actionManager.setPreferredReminderListIdentifier(nil)
            }
        }

        // Search settings
        defaultSearchEngineRawValue = actionManager.defaultSearchEngine()
        defaultAIServiceRawValue = actionManager.defaultAIService()
        searchHistory = actionManager.searchHistory()
        commandAliases = actionManager.commandAliases()
        appShortcuts = actionManager.appShortcuts()
        preferAppForSearch = actionManager.preferAppForSearch()
    }

    func updatePreferAppForSearch(_ value: Bool) {
        preferAppForSearch = value
        actionManager.setPreferAppForSearch(value)
    }

    func selectHistoryItem(_ query: String) {
        inputText = query
    }

    func removeHistoryItem(at index: Int) {
        actionManager.removeSearchHistory(at: index)
        searchHistory = actionManager.searchHistory()
    }

    func clearHistory() {
        actionManager.clearSearchHistory()
        searchHistory = []
    }

    // MARK: Command Aliases

    func addAlias(keyword: String, searchType: String) {
        actionManager.addCommandAlias(keyword: keyword, searchType: searchType)
        commandAliases = actionManager.commandAliases()
    }

    func removeAlias(id: UUID) {
        actionManager.removeCommandAlias(id: id)
        commandAliases = actionManager.commandAliases()
    }

    // MARK: App Shortcuts

    func addAppShortcut(name: String, urlScheme: String, iconName: String) {
        actionManager.addAppShortcut(name: name, urlScheme: urlScheme, iconName: iconName)
        appShortcuts = actionManager.appShortcuts()
    }

    func removeAppShortcut(id: UUID) {
        actionManager.removeAppShortcut(id: id)
        appShortcuts = actionManager.appShortcuts()
    }

    func openApp(_ shortcut: AppShortcut) {
        actionManager.openApp(shortcut)
    }

    func matchAlias(_ input: String) -> (alias: CommandAlias, query: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard !trimmed.isEmpty else { return nil }

        for alias in commandAliases.sorted(by: { $0.keyword.count > $1.keyword.count }) {
            let kw = alias.keyword.lowercased()
            if lowercased.hasPrefix(kw) {
                // 키워드 뒤가 공백이거나 문자열 끝인지 확인 (경계 매칭)
                let afterKeyword = lowercased.dropFirst(kw.count)
                guard afterKeyword.isEmpty || afterKeyword.first == " " else { continue }

                let query = String(trimmed.dropFirst(alias.keyword.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // 키워드만 입력 시 쿼리가 비어있으면 패스
                if query.isEmpty { return nil }
                return (alias, query)
            }
        }
        return nil
    }

    var matchedAliasPreview: (keyword: String, serviceName: String, query: String)? {
        guard let (alias, query) = matchAlias(inputText) else { return nil }
        return (alias.keyword, alias.searchType, query)
    }

    var shouldShowLocationShareShortcut: Bool {
        containsLocationShortcutKeyword(in: inputText)
    }

    func executeLocationShareShortcut() {
        guard containsLocationShortcutKeyword(in: inputText) else { return }
        prepareMessageChannelSelection(
            targetName: "",
            message: "",
            includeCurrentLocation: true
        )
    }

    private func prepareContactSelectionIfNeeded() -> Bool {
        guard let context = smartParser.contactSelectionContext(input: inputText) else {
            return false
        }
        guard !context.candidates.isEmpty else {
            return false
        }

        contactPickerCandidates = context.candidates
        contactSelectionKeyword = context.keyword
        pendingMessageBody = context.message
        pendingCurrentLocationFlag = context.isCurrentLocation
        isContactPickerPresented = true
        return true
    }

    private func prepareMessageChannelSelection(
        targetName: String,
        message: String,
        includeCurrentLocation: Bool
    ) {
        pendingMessageTarget = targetName
        pendingMessageTargetLabel = targetName
        pendingMessageBody = message
        pendingCurrentLocationFlag = includeCurrentLocation
        pendingHasEmail = false

        // 이메일 존재 여부 확인 후 시트 표시
        if !targetName.isEmpty {
            Task {
                pendingHasEmail = await actionManager.hasEmail(for: targetName)
                isMessageChannelSheetPresented = true
            }
        } else {
            isMessageChannelSheetPresented = true
        }
    }

    private func prepareScheduleDestinationSelection(_ parsed: ParsedSchedule) {
        pendingSchedule = parsed
        pendingScheduleTitle = parsed.title
        isScheduleDestinationSheetPresented = true
    }

    private func prepareNavigationAppSelection(origin: String?, destination: String) {
        pendingNavigationOrigin = origin
        pendingNavigationDestination = destination
        isNavigationAppSheetPresented = true
    }

    private func executePendingNavigation(type: SearchType) {
        let destination = pendingNavigationDestination
        let origin = pendingNavigationOrigin
        isNavigationAppSheetPresented = false
        pendingNavigationDestination = ""
        pendingNavigationOrigin = nil

        guard !destination.isEmpty else { return }

        // 출발지가 있으면 CLGeocoder로 좌표 변환 후 route URL 생성
        if let origin, !origin.isEmpty,
           [.mapNaver, .mapKakaoMap, .mapKakaoNavi, .mapTmap].contains(type) {
            Task {
                await actionManager.openRouteNavigation(
                    origin: origin,
                    destination: destination,
                    type: type
                )
                inputText = ""
            }
        } else {
            Task {
                await actionManager.execute(.webSearch(query: destination, type: type))
                inputText = ""
            }
        }
    }

    private func executePendingMessage(channel: ActionManager.MessageChannel) {
        let targetName = pendingMessageTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = pendingMessageBody
        let includeCurrentLocation = pendingCurrentLocationFlag

        isMessageChannelSheetPresented = false

        Task {
            await actionManager.executeMessage(
                targetName: targetName,
                message: message,
                isCurrentLocation: includeCurrentLocation,
                channel: channel,
                locationShareType: .both
            )
            inputText = ""
        }
    }

    private func executePendingSchedule(destination: ActionManager.ScheduleSaveDestination) {
        guard let pendingSchedule else {
            isScheduleDestinationSheetPresented = false
            return
        }

        isScheduleDestinationSheetPresented = false
        self.pendingSchedule = nil
        pendingScheduleTitle = ""

        Task {
            await actionManager.executeSchedule(pendingSchedule, destination: destination)
            inputText = ""
        }
    }

    private func containsLocationShortcutKeyword(in text: String) -> Bool {
        text.range(of: #"(현\s*위치|현재\s*위치|내\s*위치|현위치|내위치|위치)"#, options: .regularExpression) != nil
    }

    private func showManualNotice(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            actionNotice = message
        }

        manualNoticeResetTask?.cancel()
        manualNoticeResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                actionNotice = nil
            }
        }
    }

    // MARK: - Dictation (받아쓰기)

    func toggleDictation() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    func startDictation() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.actionManager.showNotice("음성 인식 권한이 필요합니다.")
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
        guard let recognizer, recognizer.isAvailable else {
            actionManager.showNotice("음성 인식을 사용할 수 없습니다.")
            return
        }

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            actionManager.showNotice("오디오 세션 설정 실패")
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // 자동 중지 타이머 (3초 무음 시)
        var autoStopTask: Task<Void, Never>?

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                // 기존 타이머 취소
                autoStopTask?.cancel()

                if let result {
                    self.inputText = result.bestTranscription.formattedString

                    if result.isFinal {
                        self.stopDictation()
                        return
                    }

                    // 3초 후 자동 중지 (추가 입력 없으면)
                    autoStopTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !Task.isCancelled && self.isRecording {
                            self.stopDictation()
                        }
                    }
                }

                if error != nil {
                    self.stopDictation()
                }
            }
        }

        do {
            try audioEngine.start()
            isRecording = true
            actionManager.showNotice("🎤 듣고 있습니다...")
        } catch {
            stopDictation()
            actionManager.showNotice("녹음 시작 실패")
        }
    }

    func stopDictation() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
