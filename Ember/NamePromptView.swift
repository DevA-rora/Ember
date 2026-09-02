import SwiftUI

/// First-run prompt so the session-start greeting can say "Hey there {name}"
/// instead of an email address. Shown once, right after sign-in, when no
/// profile document exists yet.
struct NamePromptView: View {
    let onSave: (String) async -> Void
    @State private var name = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 8) {
                Text("What should Ember call you?")
                    .font(.title2.bold())
                Text("Just a first name is fine — this personalizes your greeting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TextField("First name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { save() }
                .frame(maxWidth: 280)
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Continue")
                        .frame(maxWidth: 280)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            Spacer()
        }
        .padding()
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            await onSave(trimmed)
            isSaving = false
        }
    }
}
