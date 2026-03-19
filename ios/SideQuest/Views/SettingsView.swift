import SwiftUI

struct SettingsView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showSignOutConfirmation: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var showDeleteAccountConfirmation: Bool = false
    @State private var isDeletingAccount: Bool = false
    @State private var showEditProfile: Bool = false
    @State private var showSetGym: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let email = appState.auth.userEmail {
                        HStack {
                            Label("Email", systemImage: "envelope.fill")
                            Spacer()
                            Text(email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Button {
                        showEditProfile = true
                    } label: {
                        Label("Edit Profile", systemImage: "person.fill")
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy", systemImage: "lock.fill")
                    }
                }

                Section("Gym") {
                    Button {
                        showSetGym = true
                    } label: {
                        HStack {
                            Label("Default Gym", systemImage: "dumbbell.fill")
                            Spacer()
                            if let gym = appState.savedGym {
                                Text(gym.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not Set")
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Preferences") {
                    Toggle(isOn: Binding(
                        get: { appState.notificationsEnabled },
                        set: { appState.setNotificationsEnabled($0) }
                    )) {
                        Label("Notifications", systemImage: "bell.fill")
                    }

                    Toggle(isOn: Binding(
                        get: { appState.stepsEnabled },
                        set: { appState.setStepsEnabled($0) }
                    )) {
                        Label("Step Tracking", systemImage: "figure.walk")
                    }
                }



                Section("Support") {
                    NavigationLink {
                        HelpFAQView()
                    } label: {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        ReportProblemView()
                    } label: {
                        Label("Report a Problem", systemImage: "exclamationmark.bubble")
                    }
                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                    .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                appState.signOut()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("You'll need to sign in again to continue.")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "trash.fill")
                            Spacer()
                            if isDeletingAccount {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                    .confirmationDialog("Delete Account?", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
                        Button("Delete My Account", role: .destructive) {
                            isDeletingAccount = true
                            Task {
                                await appState.deleteAccount()
                                isDeletingAccount = false
                                dismiss()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete your account, progress, and all data. This cannot be undone.")
                    }
                } footer: {
                    Text("This permanently deletes your account and all associated data. This action cannot be undone.")
                }

                Section {
                    HStack {
                        Spacer()
                        Text("SideQuest v1.0.0")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(appState: appState)
            }
            .sheet(isPresented: $showSetGym) {
                SetDefaultGymSheet(appState: appState)
            }
        }
    }
}
