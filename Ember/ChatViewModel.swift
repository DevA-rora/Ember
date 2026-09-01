import Foundation
import Observation
import FirebaseAILogic

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String

    enum Role: Equatable {
        case user
        case assistant
    }
}

@MainActor
@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var input = ""
    var isThinking = false
    var errorMessage: String?

    private var chat: Chat?
    private var contextFingerprint: String = ""

    func send(contextMarkdown: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }

        do {
            try ensureChat(contextMarkdown: contextMarkdown)
            guard let chat else { return }
            let response = try await chat.sendMessage(trimmed)
            let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "I could not generate a reply."
            messages.append(ChatMessage(role: .assistant, text: text))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetConversation() {
        chat = nil
        contextFingerprint = ""
        messages = []
        errorMessage = nil
    }

    private func ensureChat(contextMarkdown: String) throws {
        if chat != nil, contextFingerprint == contextMarkdown { return }
        contextFingerprint = contextMarkdown
        let instruction = """
        You are Ember, a personal work assistant.
        Answer using the user's current Things 3 projects, tasks, notes, and deadlines below.
        If something is missing from the context, say so instead of inventing tasks.
        Prefer concise, concrete answers that cite project/task titles and dates.

        \(contextMarkdown)
        """
        let model = FirebaseAI.firebaseAI().generativeModel(
            modelName: "gemini-flash-latest",
            systemInstruction: ModelContent(role: "system", parts: instruction)
        )
        chat = model.startChat()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
