import SwiftUI
import Combine
import UIKit

@MainActor
final class OmniViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var predictedIntent: SmartIntent = .unknown
    @Published var actionNotice: String?

    private let smartParser: SmartParser
    private let actionManager: ActionManager
    private var cancellables = Set<AnyCancellable>()

    var hasPredictedIntent: Bool {
        if case .unknown = predictedIntent {
            return false
        }
        return true
    }

    init(smartParser: SmartParser = SmartParser(), actionManager: ActionManager? = nil) {
        self.smartParser = smartParser
        self.actionManager = actionManager ?? ActionManager()

        $inputText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                let parsed = self.smartParser.parse(input: text)
                withAnimation(.spring()) {
                    self.predictedIntent = parsed
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
}
