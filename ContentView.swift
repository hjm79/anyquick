import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = OmniViewModel()
    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }

            VStack(spacing: 18) {
                inputSection
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
                .background(Color.black.opacity(0.85))
                .clipShape(Capsule())
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
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task {
                await viewModel.refreshContacts()
            }
        }
    }
}

private extension ContentView {
    var inputSection: some View {
        HStack(spacing: 10) {
            TextField("명령어나 검색어를 입력하세요...", text: $viewModel.inputText)
                .font(.system(size: 19, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.go)
                .focused($isInputFocused)
                .onSubmit {
                    isInputFocused = false
                    viewModel.executePredictedIntent()
                }

            Button {
                viewModel.pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue)
            }

            if !viewModel.inputText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.inputText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }

    @ViewBuilder
    var suggestionSection: some View {
        if viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Spacer().frame(height: 120)
        } else {
            switch viewModel.predictedIntent {
            case .unknown:
                if !viewModel.contactSelectionPreview.isEmpty {
                    suggestionCard(
                        icon: "person.crop.circle.badge.checkmark",
                        title: "연락처 선택",
                        subtitle: viewModel.contactSelectionKeyword,
                        detail: viewModel.contactSelectionPreview.joined(separator: ", "),
                        color: .mint
                    )
                } else {
                    Spacer().frame(height: 120)
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
                        .fill(color.opacity(0.16))
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
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 12, y: 6)
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

    var shortcutGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            quickButton(title: "Naver", icon: "safari.fill", type: .naver)
            quickButton(title: "YouTube", icon: "play.rectangle.fill", type: .youtube)
            quickButton(title: "Netflix", icon: "film.fill", type: .netflix)
            quickButton(title: "TMDB", icon: "movieclapper.fill", type: .tmdb)
            quickButton(title: "AppStore", icon: "app.badge.fill", type: .appstore)
            quickButton(title: "Dictionary", icon: "book.fill", type: .dictionary)
        }
    }

    func quickButton(title: String, icon: String, type: SearchType) -> some View {
        Button {
            isInputFocused = false
            viewModel.executeManualSearch(type: type)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
    }

    func searchTypeLabel(_ type: SearchType) -> String {
        switch type {
        case .naver: return "Naver 검색"
        case .youtube: return "YouTube 검색"
        case .netflix: return "Netflix 검색"
        case .tmdb: return "TMDB 검색"
        case .appstore: return "App Store 검색"
        case .dictionary: return "사전 검색"
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E) a h:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}
