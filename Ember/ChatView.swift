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
                ContextSheetView(contextStore: contextStore)
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
            var detail = "\(meta.projectCount) projects · \(meta.taskCount) tasks"
            if contextStore.projects.count != meta.projectCount || contextStore.tasks.count != meta.taskCount {
                detail += " (loaded \(contextStore.projects.count)/\(contextStore.tasks.count) — tap Refresh)"
            }
            return detail
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
                        Text("Ask about what you're working on, a deadline, or a project's notes.")
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

private struct ContextSheetView: View {
    @Environment(AuthManager.self) private var auth
    let contextStore: ThingsContextStore
    @Environment(\.dismiss) private var dismiss
    @State private var showMarkdown = false

    private var tasksByProject: [String: [ThingsTask]] {
        Dictionary(grouping: contextStore.tasks.filter { $0.projectId != nil }) { $0.projectId! }
    }

    private var inboxTasks: [ThingsTask] {
        contextStore.tasks.filter(\.isInbox).sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    syncStatusHeader

                    if contextStore.usedSeedData {
                        seedSyncInstructions
                    }

                    if !contextStore.projects.isEmpty {
                        Text("Projects")
                            .font(.title3.bold())
                        ForEach(contextStore.projects.sorted { $0.sortIndex < $1.sortIndex }) { project in
                            projectSection(project)
                        }
                    }

                    if !inboxTasks.isEmpty {
                        Text("Inbox")
                            .font(.title3.bold())
                        ForEach(inboxTasks) { task in
                            taskRow(task)
                        }
                    }

                    DisclosureGroup(isExpanded: $showMarkdown) {
                        Text(contextStore.markdown)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Text("AI context markdown")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding()
            }
            .navigationTitle("Project context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var syncStatusHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let email = auth.email {
                LabeledContent("Signed in as") {
                    Text(email)
                        .textSelection(.enabled)
                }
            }
            if let uid = auth.uid {
                LabeledContent("UID") {
                    Text(uid)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if let meta = contextStore.meta {
                LabeledContent("Source") {
                    Text(meta.source == "things3" ? "Things 3" : meta.source)
                        .fontWeight(meta.source == "things3" ? .semibold : .regular)
                }
                LabeledContent("Synced") {
                    Text(meta.syncedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Counts") {
                    Text("\(meta.projectCount) projects · \(meta.taskCount) tasks")
                }
                if contextStore.projects.count != meta.projectCount || contextStore.tasks.count != meta.taskCount {
                    Text("Loaded \(contextStore.projects.count) projects, \(contextStore.tasks.count) tasks from Firestore.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No sync metadata yet")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var seedSyncInstructions: some View {
        let email = auth.email ?? "this email"
        return Text(
            "This account only has placeholder data. On your Mac, run ember-sync login with \(email), then ./scripts/sync-things-once.sh, and tap Refresh here. The UID above must match the sync script output."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func projectSection(_ project: ThingsProject) -> some View {
        let nested = (tasksByProject[project.uuid] ?? []).sorted { $0.sortIndex < $1.sortIndex }
        return VStack(alignment: .leading, spacing: 8) {
            Text(project.title)
                .font(.headline)
            if let deadline = project.deadline {
                Text("Deadline \(deadline)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let area = project.area, !area.isEmpty {
                Text("Area: \(area)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !project.notes.isEmpty {
                Text(project.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if nested.isEmpty {
                Text("No open tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("\(nested.count) open tasks")
                    .font(.caption.weight(.medium))
                ForEach(nested) { task in
                    taskRow(task, indented: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func taskRow(_ task: ThingsTask, indented: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .font(indented ? .subheadline : .headline)
            if let deadline = task.deadline {
                Text("Deadline \(deadline)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !task.notes.isEmpty {
                Text(task.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, indented ? 12 : 0)
    }
}

private extension Color {
    static var fill: Color { Color.primary }
}
