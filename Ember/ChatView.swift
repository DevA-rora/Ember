import SwiftUI

struct ChatView: View {
    @Environment(AuthManager.self) private var auth
    @State private var contextStore = ThingsContextStore()
    @State private var chat = ChatViewModel()
    @State private var showContext = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextBanner
                Divider()
                messageList
                if let error = chat.errorMessage ?? contextStore.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                composer
            }
            .navigationTitle("Ember")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Context") { showContext = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let email = auth.email {
                            Text(email)
                        }
                        if let uid = auth.uid {
                            Text("uid \(uid)")
                        }
                        Button("Refresh projects") {
                            Task { await reload() }
                        }
                        Button("New chat") { chat.resetConversation() }
                        Button("Sign out", role: .destructive) { auth.signOut() }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showContext) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if contextStore.usedSeedData {
                                Text("Showing seeded Firebase fixture until Things 3 sync runs.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(contextStore.projects) { project in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title).font(.headline)
                                    if let deadline = project.deadline {
                                        Text("Deadline \(deadline)").font(.subheadline)
                                    }
                                    if !project.notes.isEmpty {
                                        Text(project.notes).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            ForEach(contextStore.tasks) { task in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).font(.headline)
                                    if let deadline = task.deadline {
                                        Text("Deadline \(deadline)").font(.subheadline)
                                    }
                                    if !task.notes.isEmpty {
                                        Text(task.notes).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Text(contextStore.markdown)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding()
                    }
                    .navigationTitle("Project context")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showContext = false }
                        }
                    }
                }
            }
            .task(id: auth.uid) {
                await reload()
            }
        }
    }

    private var contextBanner: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contextStore.usedSeedData ? "Seeded project context" : "Things 3 context")
                    .font(.caption.weight(.semibold))
                Text(bannerDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if contextStore.isLoading {
                ProgressView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var bannerDetail: String {
        if let meta = contextStore.meta {
            return "\(meta.projectCount) projects · \(meta.taskCount) tasks"
        }
        if contextStore.projects.isEmpty && contextStore.tasks.isEmpty {
            return "No projects loaded yet"
        }
        return "\(contextStore.projects.count) projects · \(contextStore.tasks.count) tasks"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        Text("Ask about what you’re working on, a deadline, or a project’s notes.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                    ForEach(chat.messages) { message in
                        HStack {
                            if message.role == .user { Spacer(minLength: 40) }
                            Text(message.text)
                                .padding(12)
                                .background(message.role == .user ? Color.accentColor.opacity(0.15) : Color.fill.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                            if message.role == .assistant { Spacer(minLength: 40) }
                        }
                        .id(message.id)
                    }
                    if chat.isThinking {
                        ProgressView()
                            .id("thinking")
                    }
                }
                .padding()
            }
            .onChange(of: chat.messages.count) {
                if let last = chat.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom) {
            TextField("Ask about a project or deadline", text: $chat.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
            Button {
                Task { await chat.send(contextMarkdown: contextStore.markdown) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(chat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isThinking)
        }
        .padding()
    }

    private func reload() async {
        guard let uid = auth.uid else { return }
        chat.resetConversation()
        await contextStore.refresh(uid: uid)
    }
}

private extension Color {
    static var fill: Color { Color.primary }
}
