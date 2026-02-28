import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = OmniViewModel()
    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isScheduleSettingsPresented: Bool = false
    @State private var selectedShortcutCategory: ShortcutCategory? = nil
    @State private var isAddAliasPresented: Bool = false
    @State private var newAliasKeyword: String = ""
    @State private var newAliasSearchType: String = "naver"

    private enum ShortcutCategory {
        case webSearch
        case shopping
        case ai
        case map
        case dictionary
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.14),
                    Color(red: 0.08, green: 0.10, blue: 0.22),
                    Color(red: 0.05, green: 0.06, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }

            VStack(spacing: 18) {
                inputSection
                if !viewModel.searchHistory.isEmpty && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHistorySection
                }
                suggestionSection
                shortcutGrid
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.actionNotice {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                    Text(notice)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                isInputFocused = true
            }
        }
        .sheet(isPresented: $viewModel.isContactPickerPresented) {
            contactPickerSheet
        }
        .sheet(isPresented: $isScheduleSettingsPresented) {
            scheduleSettingsSheet
        }
        .confirmationDialog(
            "전송 방식을 선택하세요",
            isPresented: $viewModel.isMessageChannelSheetPresented,
            titleVisibility: .visible
        ) {
            Button("문자로 보내기") {
                isInputFocused = false
                viewModel.sendPendingMessageAsSMS()
            }
            Button("앱 선택해서 공유하기") {
                isInputFocused = false
                viewModel.sendPendingMessageAsAppShare()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelPendingMessageSelection()
            }
        } message: {
            if viewModel.pendingMessageTargetLabel.isEmpty {
                Text("문자 또는 공유 시트에서 카카오톡 등 앱을 선택할 수 있습니다.")
            } else {
                Text("\(viewModel.pendingMessageTargetLabel)에게 보낼 메시지를 문자 또는 공유 앱으로 전송합니다.")
            }
        }
        .confirmationDialog(
            "등록 방식을 선택하세요",
            isPresented: $viewModel.isScheduleDestinationSheetPresented,
            titleVisibility: .visible
        ) {
            Button("일정으로 등록") {
                isInputFocused = false
                viewModel.registerPendingScheduleAsCalendarEvent()
            }
            Button("미리알림으로 등록") {
                isInputFocused = false
                viewModel.registerPendingScheduleAsReminder()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelPendingScheduleSelection()
            }
        } message: {
            if viewModel.pendingScheduleTitle.isEmpty {
                Text("캘린더 일정 또는 미리알림 중 저장 방식을 선택하세요.")
            } else {
                Text("\"\(viewModel.pendingScheduleTitle)\"를 어디에 등록할지 선택하세요.")
            }
        }
        .confirmationDialog(
            "내비게이션 앱을 선택하세요",
            isPresented: $viewModel.isNavigationAppSheetPresented,
            titleVisibility: .visible
        ) {
            Button("카카오맵 검색") {
                isInputFocused = false
                viewModel.navigateWithKakaoMap()
            }
            Button("카카오내비") {
                isInputFocused = false
                viewModel.navigateWithKakaoNavi()
            }
            Button("티맵 검색") {
                isInputFocused = false
                viewModel.navigateWithTmap()
            }
            Button("네이버맵 검색") {
                isInputFocused = false
                viewModel.navigateWithNaverMap()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelNavigationAppSelection()
            }
        } message: {
            if viewModel.pendingNavigationDestination.isEmpty {
                Text("길안내에 사용할 앱을 선택하세요.")
            } else {
                Text("\"\(viewModel.pendingNavigationDestination)\" 길안내에 사용할 앱을 선택하세요.")
            }
        }
        .confirmationDialog(
            "검색할 서비스를 선택하세요",
            isPresented: $viewModel.isWebSearchSheetPresented,
            titleVisibility: .visible
        ) {
            Button("Naver 검색") {
                isInputFocused = false
                viewModel.searchWithNaver()
            }
            Button("Google 검색") {
                isInputFocused = false
                viewModel.searchWithGoogle()
            }
            Button("YouTube 검색") {
                isInputFocused = false
                viewModel.searchWithYouTube()
            }
            Button("App Store 검색") {
                isInputFocused = false
                viewModel.searchWithAppStore()
            }
            Button("ChatGPT") {
                isInputFocused = false
                viewModel.searchWithChatGPT()
            }
            Button("Perplexity") {
                isInputFocused = false
                viewModel.searchWithPerplexity()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelWebSearchSelection()
            }
        } message: {
            Text("\"\(viewModel.cleanedInputText)\" 검색할 서비스를 선택하세요.")
        }
        .confirmationDialog(
            "AI 서비스를 선택하세요",
            isPresented: $viewModel.isAIAppSheetPresented,
            titleVisibility: .visible
        ) {
            Button("ChatGPT") {
                isInputFocused = false
                viewModel.aiWithChatGPT()
            }
            Button("Gemini") {
                isInputFocused = false
                viewModel.aiWithGemini()
            }
            Button("Claude") {
                isInputFocused = false
                viewModel.aiWithClaude()
            }
            Button("Perplexity") {
                isInputFocused = false
                viewModel.aiWithPerplexity()
            }
            Button("Grok") {
                isInputFocused = false
                viewModel.aiWithGrok()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelAIAppSelection()
            }
        } message: {
            if viewModel.pendingAIQuery.isEmpty {
                Text("질문할 AI 서비스를 선택하세요.")
            } else {
                Text("\"\(viewModel.pendingAIQuery)\" 질문할 AI 서비스를 선택하세요.")
            }
        }
        .onOpenURL { url in
            handleURLScheme(url)
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.refreshContacts()
            }
        }
        .onChange(of: viewModel.inputText) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedShortcutCategory = nil
            }
        }
    }
}

private extension ContentView {
    var inputSection: some View {
        HStack(spacing: 12) {
            TextField("검색어를 입력하세요", text: $viewModel.inputText)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .tint(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.go)
                .focused($isInputFocused)
                .onSubmit {
                    isInputFocused = false
                    viewModel.executePredictedIntent()
                }

            if viewModel.inputText.isEmpty && !viewModel.isRecording {
                // 입력 비어있을 때: 받아쓰기 + 클립보드
                Button {
                    viewModel.toggleDictation()
                } label: {
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 32, height: 32)
                }

                Button {
                    viewModel.pasteFromClipboard()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .frame(width: 32, height: 32)
                }
            } else if viewModel.isRecording {
                // 녹음 중: 정지 버튼
                Button {
                    viewModel.toggleDictation()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.red)
                        .opacity(0.8)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: viewModel.isRecording)
                }
            } else {
                // 텍스트 있을 때: 지우기만
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        viewModel.inputText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isInputFocused
                                ? Color(red: 0.4, green: 0.6, blue: 1.0).opacity(0.45)
                                : Color.white.opacity(0.1),
                            lineWidth: isInputFocused ? 1 : 0.5
                        )
                )
        }
    }

    @ViewBuilder
    var suggestionSection: some View {
        if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Spacer().frame(height: 120)
        } else {
            switch viewModel.predictedIntent {
            case .unknown:
                if let preview = viewModel.matchedAliasPreview {
                    suggestionCard(
                        icon: "link",
                        title: "별칭: \(preview.keyword)",
                        subtitle: preview.query,
                        detail: "\(searchTypeLabel(SearchType(rawValue: preview.serviceName) ?? .naver)) 검색",
                        color: .indigo
                    )
                } else if !viewModel.contactSelectionPreview.isEmpty {
                    suggestionCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "연락처 선택",
                        subtitle: viewModel.contactSelectionKeyword,
                        detail: viewModel.contactSelectionPreview.joined(separator: ", "),
                        color: .mint
                    )
                } else {
                    suggestionCard(
                        icon: "magnifyingglass",
                        title: "웹 검색",
                        subtitle: viewModel.cleanedInputText,
                        detail: viewModel.defaultSearchEngineRawValue != nil
                            ? "\(searchTypeLabel(SearchType(rawValue: viewModel.defaultSearchEngineRawValue!) ?? .naver)) 검색"
                            : "서비스 선택",
                        color: .purple
                    )
                }
            case .addSchedule(let schedule):
                suggestionCard(
                    icon: "calendar.badge.plus",
                    title: "일정 등록",
                    subtitle: schedule.title,
                    detail: formatDate(schedule.start),
                    color: .orange
                )
            case .sendMessage(let targetName, let message, let isCurrentLocation):
                suggestionCard(
                    icon: "message.fill",
                    title: "메시지 발송",
                    subtitle: targetName,
                    detail: isCurrentLocation ? "\(message) · 카카오/네이버 위치링크 포함" : message,
                    color: .green
                )
            case .navigation(let destination):
                suggestionCard(
                    icon: "car.fill",
                    title: "길안내 시작",
                    subtitle: destination,
                    detail: "탭하면 내비게이션을 실행해요",
                    color: .blue
                )
            case .webSearch(let query, let type):
                suggestionCard(
                    icon: "magnifyingglass",
                    title: "웹 검색",
                    subtitle: query,
                    detail: searchTypeLabel(type),
                    color: .purple
                )
            }
        }
    }

    func suggestionCard(icon: String, title: String, subtitle: String, detail: String, color: Color) -> some View {
        Button {
            isInputFocused = false
            viewModel.executePredictedIntent()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(color)
                }
                .frame(width: 62, height: 62)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                    Text(subtitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(color.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.15), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    var contactPickerSheet: some View {
        NavigationView {
            List(viewModel.contactPickerCandidates, id: \.self) { name in
                Button {
                    isInputFocused = false
                    viewModel.selectContactCandidate(name)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                        Text(name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("연락처 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        viewModel.cancelContactSelection()
                    }
                }
            }
        }
    }

    var scheduleSettingsSheet: some View {
        NavigationView {
            List {
                Section("일정") {
                    Picker("캘린더", selection: calendarBinding) {
                        Text("기본 캘린더").tag(nil as String?)
                        ForEach(viewModel.eventCalendarOptions) { calendar in
                            Text(calendar.title).tag(calendar.id as String?)
                        }
                    }

                    Picker("미리알림 목록", selection: reminderBinding) {
                        Text("기본 목록").tag(nil as String?)
                        ForEach(viewModel.reminderListOptions) { list in
                            Text(list.title).tag(list.id as String?)
                        }
                    }
                }

                Section {
                    Picker("기본 검색 엔진", selection: searchEngineBinding) {
                        Text("선택 시트 표시").tag(nil as String?)
                        ForEach(defaultSearchEngineOptions, id: \.rawValue) { option in
                            Text(searchTypeLabel(option)).tag(option.rawValue as String?)
                        }
                    }

                    Picker("기본 AI 서비스", selection: aiServiceBinding) {
                        Text("선택 시트 표시").tag(nil as String?)
                        ForEach(defaultAIServiceOptions, id: \.rawValue) { option in
                            Text(searchTypeLabel(option)).tag(option.rawValue as String?)
                        }
                    }

                    Toggle("앱 우선 실행", isOn: appSearchBinding)
                } header: {
                    Text("검색")
                } footer: {
                    Text("네이버·구글·퍼플렉시티 검색에 적용됩니다.\n켜면 앱이 설치된 경우 앱에서, 끄면 웹 브라우저로 열립니다.")
                }

                Section {
                    ForEach(viewModel.commandAliases) { alias in
                        HStack {
                            Text(alias.keyword)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(searchTypeLabel(SearchType(rawValue: alias.searchType) ?? .naver))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let alias = viewModel.commandAliases[index]
                            viewModel.removeAlias(id: alias.id)
                        }
                    }

                    Button {
                        newAliasKeyword = ""
                        newAliasSearchType = "naver"
                        isAddAliasPresented = true
                    } label: {
                        Label("별칭 추가", systemImage: "plus.circle")
                    }
                } header: {
                    Text("커맨드 별칭")
                } footer: {
                    Text("입력 시 별칭 키워드로 시작하면 해당 서비스로 바로 검색\n예: \"yt 강남맛집\" → YouTube 검색")
                }
            }
            .navigationTitle("환경설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        isScheduleSettingsPresented = false
                    }
                }
            }
            .task {
                await viewModel.loadSettings()
            }
            .sheet(isPresented: $isAddAliasPresented) {
                NavigationView {
                    Form {
                        Section("키워드") {
                            TextField("예: yt, 맛집, wiki", text: $newAliasKeyword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }

                        Section("서비스") {
                            Picker("검색 서비스", selection: $newAliasSearchType) {
                                ForEach(aliasServiceOptions, id: \.rawValue) { option in
                                    Text(searchTypeLabel(option)).tag(option.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                    .navigationTitle("별칭 추가")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("취소") {
                                isAddAliasPresented = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("추가") {
                                viewModel.addAlias(keyword: newAliasKeyword, searchType: newAliasSearchType)
                                isAddAliasPresented = false
                            }
                            .disabled(newAliasKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private var calendarBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedEventCalendarIdentifier },
            set: { viewModel.updatePreferredEventCalendar(identifier: $0) }
        )
    }

    private var reminderBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedReminderListIdentifier },
            set: { viewModel.updatePreferredReminderList(identifier: $0) }
        )
    }

    private var searchEngineBinding: Binding<String?> {
        Binding(
            get: { viewModel.defaultSearchEngineRawValue },
            set: { viewModel.updateDefaultSearchEngine($0) }
        )
    }

    private var aiServiceBinding: Binding<String?> {
        Binding(
            get: { viewModel.defaultAIServiceRawValue },
            set: { viewModel.updateDefaultAIService($0) }
        )
    }

    private var appSearchBinding: Binding<Bool> {
        Binding(
            get: { viewModel.preferAppForSearch },
            set: { viewModel.updatePreferAppForSearch($0) }
        )
    }

    var searchHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("최근 검색")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Button("전체 삭제") {
                    viewModel.clearHistory()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.searchHistory.enumerated()), id: \.offset) { index, query in
                        Button {
                            viewModel.selectHistoryItem(query)
                        } label: {
                            Text(query)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.removeHistoryItem(at: index)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var defaultSearchEngineOptions: [SearchType] {
        [.naver, .google, .perplexity]
    }

    private var defaultAIServiceOptions: [SearchType] {
        [.chatgpt, .gemini, .claude, .perplexity, .grok]
    }

    private var aliasServiceOptions: [SearchType] {
        [.naver, .google, .youtube, .appstore, .chatgpt, .gemini, .claude, .perplexity, .grok, .dictionaryEnglish, .dictionaryKorean, .dictionaryHanja]
    }

    private func handleURLScheme(_ url: URL) {
        guard url.scheme == "anyquick" else { return }

        switch url.host {
        case "search":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItem = components.queryItems?.first(where: { $0.name == "q" }),
                  let query = queryItem.value, !query.isEmpty else { return }

            viewModel.inputText = query

            if let typeItem = components.queryItems?.first(where: { $0.name == "type" }),
               let typeValue = typeItem.value,
               let searchType = SearchType(rawValue: typeValue) {
                viewModel.executeManualSearch(type: searchType)
            }
        default:
            break
        }
    }

    var shortcutGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                if viewModel.shouldShowLocationShareShortcut {
                    locationShareQuickButton
                }
                categoryButton(title: "웹검색", icon: "magnifyingglass", category: .webSearch)
                categoryButton(title: "쇼핑", icon: "cart.fill", category: .shopping)
                categoryButton(title: "AI", icon: "sparkles", category: .ai)
                categoryButton(title: "지도", icon: "map.fill", category: .map)
                categoryButton(title: "사전", icon: "character.book.closed.fill", category: .dictionary)
                reminderQuickButton
            }

            if let selectedShortcutCategory {
                LazyVGrid(columns: columns, spacing: 12) {
                    switch selectedShortcutCategory {
                    case .webSearch:
                        quickButton(title: "Naver", icon: "safari.fill", type: .naver)
                        quickButton(title: "Google", icon: "globe", type: .google)
                        quickButton(title: "YouTube", icon: "play.rectangle.fill", type: .youtube)
                        quickButton(title: "TMDB", icon: "film.fill", type: .tmdb)
                        quickButton(title: "AppStore", icon: "app.badge.fill", type: .appstore)
                    case .shopping:
                        quickButton(title: "네이버쇼핑", icon: "bag.fill", type: .shoppingNaver)
                        quickButton(title: "Coupang", icon: "cart.badge.plus", type: .coupang)
                        quickButton(title: "AliExpress", icon: "shippingbox.fill", type: .aliexpress)
                    case .ai:
                        quickButton(title: "ChatGPT", icon: "message.fill", type: .chatgpt)
                        quickButton(title: "Gemini", icon: "sparkles", type: .gemini)
                        quickButton(title: "Claude", icon: "text.bubble.fill", type: .claude)
                        quickButton(title: "Perplexity", icon: "questionmark.circle.fill", type: .perplexity)
                        quickButton(title: "Grok", icon: "bolt.fill", type: .grok)
                    case .map:
                        quickButton(title: "NaverMap", icon: "map", type: .mapNaver)
                        quickButton(title: "KakaoMap", icon: "mappin.and.ellipse", type: .mapKakaoMap)
                        quickButton(title: "카카오길안내", icon: "location.north.line.fill", type: .mapKakaoNavi)
                        quickButton(title: "Tmap", icon: "car.fill", type: .mapTmap)
                    case .dictionary:
                        quickButton(title: "영어사전", icon: "textformat.abc", type: .dictionaryEnglish)
                        quickButton(title: "국어사전", icon: "character.ko", type: .dictionaryKorean)
                        quickButton(title: "한자사전", icon: "character.zh", type: .dictionaryHanja)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // 설정 버튼
            Button {
                isInputFocused = false
                isScheduleSettingsPresented = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                    Text("설정")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
    }

    var locationShareQuickButton: some View {
        Button {
            isInputFocused = false
            viewModel.executeLocationShareShortcut()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("위치공유")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    var reminderQuickButton: some View {
        Button {
            isInputFocused = false
            viewModel.executeReminderShortcut()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text("미리알림")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Color.cyan.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasInputText)
        .opacity(hasInputText ? 1.0 : 0.4)
    }

    private func categoryColor(for category: ShortcutCategory) -> Color {
        switch category {
        case .webSearch: return .blue
        case .shopping: return .orange
        case .ai: return .purple
        case .map: return .green
        case .dictionary: return .mint
        }
    }

    private func categoryButton(title: String, icon: String, category: ShortcutCategory) -> some View {
        let isSelected = selectedShortcutCategory == category
        let brandColor = categoryColor(for: category)

        return Button {
            isInputFocused = false
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedShortcutCategory = isSelected ? nil : category
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? brandColor : Color.white.opacity(0.8))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(isSelected ? brandColor : Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isSelected
                                ? [brandColor.opacity(0.22), brandColor.opacity(0.08)]
                                : [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .top) {
                        // 상단 하이라이트 라인
                        Capsule()
                            .fill(isSelected ? brandColor.opacity(0.5) : Color.white.opacity(0.08))
                            .frame(width: 40, height: 2)
                            .padding(.top, 4)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? brandColor.opacity(0.35) : Color.white.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasInputText)
        .opacity(hasInputText ? 1.0 : 0.4)
    }

    private func brandColor(for type: SearchType) -> Color {
        switch type {
        case .naver, .shoppingNaver: return Color(red: 0.01, green: 0.78, blue: 0.35)
        case .google: return Color(red: 0.26, green: 0.52, blue: 0.96)
        case .youtube: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .netflix: return Color(red: 0.89, green: 0.09, blue: 0.14)
        case .coupang: return Color(red: 0.89, green: 0.10, blue: 0.22)
        case .chatgpt: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .gemini: return Color(red: 0.53, green: 0.62, blue: 1.0)
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.30)
        case .perplexity: return Color(red: 0.13, green: 0.69, blue: 0.87)
        case .grok: return Color.white
        case .aliexpress: return Color(red: 0.91, green: 0.31, blue: 0.09)
        case .tmdb: return Color(red: 0.01, green: 0.82, blue: 0.73)
        case .dictionaryEnglish: return .blue
        case .dictionaryKorean: return .mint
        case .dictionaryHanja: return .orange
        default: return Color.white.opacity(0.8)
        }
    }

    func quickButton(title: String, icon: String, type: SearchType) -> some View {
        let color = brandColor(for: type)
        return Button {
            isInputFocused = false
            viewModel.executeManualSearch(type: type)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.16), color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(color.opacity(0.35))
                            .frame(width: 30, height: 2)
                            .padding(.top, 4)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasInputText)
        .opacity(hasInputText ? 1.0 : 0.4)
    }

    func searchTypeLabel(_ type: SearchType) -> String {
        switch type {
        case .naver: return "Naver 검색"
        case .youtube: return "YouTube 검색"
        case .netflix: return "Netflix 검색"
        case .tmdb: return "TMDB 검색"
        case .appstore: return "App Store 검색"
        case .dictionary: return "사전 검색"
        case .dictionaryEnglish: return "영어사전"
        case .dictionaryKorean: return "국어사전"
        case .dictionaryHanja: return "한자사전"
        case .google: return "Google 검색"
        case .shoppingNaver: return "네이버쇼핑"
        case .coupang: return "Coupang 검색"
        case .aliexpress: return "AliExpress 검색"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .perplexity: return "Perplexity"
        case .grok: return "Grok"
        case .mapNaver: return "네이버맵 검색"
        case .mapKakaoMap: return "카카오맵 검색"
        case .mapKakaoNavi: return "카카오길안내"
        case .mapTmap: return "티맵 길안내"
        }
    }

    var hasInputText: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E) a h:mm"
        return f
    }()

    func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
