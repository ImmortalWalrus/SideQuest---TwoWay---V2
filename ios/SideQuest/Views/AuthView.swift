import SwiftUI

struct AuthView: View {
    let appState: AppState
    @State private var mode: AuthMode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showForgotPassword: Bool = false
    @State private var resetEmailSent: Bool = false
    @State private var resetEmail: String = ""
    @State private var isGoogleLoading: Bool = false

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    .black, .indigo.opacity(0.3), .black,
                    .red.opacity(0.2), .black, .green.opacity(0.2),
                    .black, .blue.opacity(0.2), .black
                ]
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)

                    VStack(spacing: 12) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 56))
                            .foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))

                        Text("SideQuest")
                            .font(.system(.largeTitle, design: .default, weight: .black))
                            .foregroundStyle(.white)
                    }

                    Picker("", selection: $mode) {
                        Text("Sign In").tag(AuthMode.signIn)
                        Text("Create Account").tag(AuthMode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    VStack(spacing: 14) {
                        AuthTextField(
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $email,
                            isSecure: false,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress
                        )

                        AuthTextField(
                            icon: "lock.fill",
                            placeholder: "Password",
                            text: $password,
                            isSecure: true,
                            textContentType: mode == .signUp ? .newPassword : .password
                        )

                        if mode == .signUp {
                            AuthTextField(
                                icon: "lock.shield.fill",
                                placeholder: "Confirm Password",
                                text: $confirmPassword,
                                isSecure: true,
                                textContentType: .newPassword
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    if let error = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 28)
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    VStack(spacing: 12) {
                        Button {
                            handleAuth()
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(mode == .signIn ? "Sign In" : "Create Account")
                                        .font(.headline)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || !isFormValid)

                        if mode == .signIn {
                            Button {
                                resetEmail = email
                                showForgotPassword = true
                            } label: {
                                Text("Forgot Password?")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 1)
                        Text("or")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                        Rectangle()
                            .fill(.white.opacity(0.15))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 24)

                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 10) {
                            if isGoogleLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text("Continue with Google")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .disabled(isLoading || isGoogleLoading)
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.spring(response: 0.35), value: mode)
        .animation(.easeOut(duration: 0.25), value: errorMessage != nil)
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $resetEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Send Reset Link") {
                sendPasswordReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your email and we'll send a link to reset your password.")
        }
        .alert("Check Your Email", isPresented: $resetEmailSent) {
            Button("OK") {}
        } message: {
            Text("If an account exists for that email, a password reset link has been sent.")
        }
        .onChange(of: mode) { _, _ in
            errorMessage = nil
        }
    }

    private var isFormValid: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            guard password.count >= 6, password == confirmPassword else { return false }
        }
        return true
    }

    private func handleAuth() {
        guard isFormValid else { return }
        isLoading = true
        errorMessage = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        Task {
            do {
                if mode == .signUp {
                    try await appState.firebase.signUpWithEmail(trimmedEmail, password: password)
                    appState.onAuthCompleted(isNewUser: true)
                    appState.onAuthCompleted(isNewUser: true)
                } else {
                    try await appState.firebase.signInWithEmail(trimmedEmail, password: password)
                    appState.onAuthCompleted(isNewUser: false)
                    appState.onAuthCompleted(isNewUser: false)
                }
            } catch {
                errorMessage = appState.firebase.authError ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func sendPasswordReset() {
        let trimmedEmail = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedEmail.isEmpty else { return }
        Task {
            try? await appState.firebase.sendPasswordReset(email: trimmedEmail)
            resetEmailSent = true
        }
    }

    private func handleGoogleSignIn() {
        isGoogleLoading = true
        errorMessage = nil
        Task {
            do {
                try await appState.firebase.signInWithGoogle()
                appState.onAuthCompleted(isNewUser: false)

            } catch {
                errorMessage = appState.firebase.authError ?? error.localizedDescription
            }
            isGoogleLoading = false
        }
    }
}

struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    @State private var showPassword: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 20)

            Group {
                if isSecure && !showPassword {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                }
            }
            .textContentType(textContentType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .foregroundStyle(.white)
            .tint(.blue)

            if isSecure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
        }
    }
}

nonisolated enum AuthMode: Sendable {
    case signIn
    case signUp
}
