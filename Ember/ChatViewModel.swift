import Foundation
import Observation
import FirebaseAILogic

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    /// Buttons offered alongside this message, e.g. the three readiness paths
    /// ("Of course" / "I guess" / "Not yet") on the session-start greeting.
    var quickReplies: [String]? = nil

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

    /// Posts a deterministic opening turn — no model call — naming the user and
    /// a suggested task, with the three readiness buttons. Deterministic rather
    /// than model-generated keeps it instant, free, and always on-format; the
    /// model only takes over once a readiness path is chosen. No-op if a
    /// conversation is already underway.
    func startSession(displayName: String?, suggestion: TaskSuggestion?) {
        guard messages.isEmpty else { return }
        let name = displayName ?? "there"
        let greeting = suggestion.map { "Hey \(name), ready to work on \u{201C}\($0.task.title)\u{201D}?" }
            ?? "Hey \(name), what would you like to work on?"
        messages.append(
            ChatMessage(role: .assistant, text: greeting, quickReplies: ["Of course", "I guess", "Not yet"])
        )
    }

    /// Sends a tapped quick-reply button as if the user had typed it.
    func selectQuickReply(_ reply: String, systemInstruction: String) async {
        input = reply
        await send(systemInstruction: systemInstruction)
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
