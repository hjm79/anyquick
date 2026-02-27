import SwiftUI
import Combine
import UIKit

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
    @Published var pendingMessageTargetLabel: String = ""

    private let smartParser: SmartParser
    private let actionManager: ActionManager
    private var cancellables = Set<AnyCancellable>()
    private var pendingMessageTarget: String = ""
    private var pendingMessageBody: String = ""
    private var pendingCurrentLocationFlag: Bool = false

    init(smartParser: SmartParser = SmartParser(), actionManager: ActionManager? = nil) {
        self.smartParser = smartParser
        self.actionManager = actionManager ?? ActionManager()

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

        actionManager.$actionNotice
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
        if case .unknown = predictedIntent, prepareContactSelectionIfNeeded() {
            return
        }

        if case .sendMessage(let targetName, let message, let isCurrentLocation) = predictedIntent {
            prepareMessageChannelSelection(
                targetName: targetName,
                message: message,
                includeCurrentLocation: isCurrentLocation
            )
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

        Task {
            await actionManager.execute(.webSearch(query: trimmed, type: type))
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

    func cancelPendingMessageSelection() {
        isMessageChannelSheetPresented = false
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
        isMessageChannelSheetPresented = true
    }

    private func executePendingMessage(channel: ActionManager.MessageChannel) {
        guard !pendingMessageTarget.isEmpty else {
            isMessageChannelSheetPresented = false
            return
        }

        let targetName = pendingMessageTarget
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
}
