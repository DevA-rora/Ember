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

    /// `systemInstruction` should be the full string from `EmberContextAssembler`,
    /// not just the Things markdown — fingerprinting the whole thing means any
    /// layer changing (knowledge, memory, calendar, suggestion) invalidates the chat.
    func send(systemInstruction: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        input = ""
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }

        do {
            try ensureChat(systemInstruction: systemInstruction)
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

    private func ensureChat(systemInstruction: String) throws {
        if chat != nil, contextFingerprint == systemInstruction { return }
        contextFingerprint = systemInstruction
        let model = FirebaseAI.firebaseAI().generativeModel(
            modelName: "gemini-flash-latest",
            systemInstruction: ModelContent(role: "system", parts: systemInstruction)
        )
        chat = model.startChat()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
