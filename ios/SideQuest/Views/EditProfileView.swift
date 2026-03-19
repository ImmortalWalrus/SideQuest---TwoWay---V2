import SwiftUI

struct EditProfileView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var username: String = ""
    @State private var selectedAvatar: String = ""

    private let avatars = [
        "figure.run", "figure.hiking", "figure.martial.arts",
        "figure.strengthtraining.traditional", "figure.mind.and.body",
        "figure.walk", "figure.cooldown", "figure.yoga",
        "figure.fencing", "figure.climbing"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(.linearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 80, height: 80)
                            Image(systemName: selectedAvatar)
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                        ForEach(avatars, id: \.self) { avatar in
                            Button {
                                selectedAvatar = avatar
                            } label: {
                                Image(systemName: avatar)
                                    .font(.title3)
                                    .foregroundStyle(selectedAvatar == avatar ? .white : .secondary)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        selectedAvatar == avatar ? Color.blue : Color(.tertiarySystemGroupedBackground),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Username") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            appState.updateProfile(username: trimmed, avatar: selectedAvatar)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                username = appState.profile.username
                selectedAvatar = appState.profile.avatarName
            }
        }
    }
}
