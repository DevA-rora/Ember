import SwiftUI

struct AuthView: View {
    @Environment(AuthManager.self) private var auth
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("Ember")
                    .font(.largeTitle.bold())
                Text("Sign in to load your projects, deadlines, and chat context.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding(12)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            if let error = auth.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 10) {
                Button {
                    Task { await auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                } label: {
                    label("Sign in")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || auth.isBusy)

                Button("Create account") {
                    Task { await auth.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password) }
                }
                .disabled(!canSubmit || auth.isBusy)
            }

            if auth.isBusy {
                ProgressView()
            }

            Spacer()
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}
