import SwiftUI
import Combine
import UIKit

@MainActor
final class OmniViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var predictedIntent: SmartIntent = .unknown

    private let smartParser: SmartParser
    private let actionManager: ActionManager
    private var cancellables = Set<AnyCancellable>()

    init(smartParser: SmartParser = SmartParser(), actionManager: ActionManager = ActionManager()) {
        self.smartParser = smartParser
        self.actionManager = actionManager

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
    }

    func executePredictedIntent() {
        Task {
            await actionManager.execute(predictedIntent)
        }
    }

    func executeManualSearch(type: SearchType) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            await actionManager.execute(.webSearch(query: trimmed, type: type))
        }
    }

    func pasteFromClipboard() {
        if let clipboard = UIPasteboard.general.string {
            inputText = clipboard
        }
    }
}
