import SwiftUI

struct ReferralView: View {
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var referralCode: String = ""
    @State private var copied: Bool = false
    @State private var redeemCode: String = ""
    @State private var isRedeeming: Bool = false
    @State private var redeemResult: String?
    @State private var redeemSuccess: Bool = false
    @State private var showRedeemResult: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    codeSection
                    redeemSection
                    statsSection
                    howItWorksSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Referrals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                referralCode = appState.generateReferralCode()
                Task {
                    if let serverCode = await appState.fetchServerReferralCode() {
                        referralCode = serverCode
                    }
                }
            }
            .alert(redeemSuccess ? "Code Redeemed!" : "Redemption Failed", isPresented: $showRedeemResult) {
                Button("OK") {}
            } message: {
                Text(redeemResult ?? "")
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.badge.gearshape.fill")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Invite Friends")
                .font(.title2.weight(.bold))

            Text("Share your code and earn rewards when friends join and complete their first quest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }

    private var codeSection: some View {
        VStack(spacing: 12) {
            Text("Your Referral Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(referralCode)
                .font(.title3.weight(.heavy).monospaced())
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = referralCode
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(copied ? .green : .blue)
                .sensoryFeedback(.success, trigger: copied)

                ShareLink(item: "Join me on SideQuest! Use my referral code: \(referralCode)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var redeemSection: some View {
        VStack(spacing: 12) {
            Text("Have a Code?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                TextField("Enter referral code", text: $redeemCode)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                Button {
                    guard !redeemCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    isRedeeming = true
                    Task {
                        if let result = await appState.redeemReferralCode(redeemCode.trimmingCharacters(in: .whitespaces)) {
                            redeemSuccess = result.success
                            if result.success {
                                redeemResult = "You earned \(result.bonusGold ?? 100) bonus gold!"
                                redeemCode = ""
                            } else {
                                redeemResult = result.reason ?? "Invalid or already used code."
                            }
                        } else {
                            redeemSuccess = false
                            redeemResult = "Unable to redeem. Check your connection."
                        }
                        isRedeeming = false
                        showRedeemResult = true
                    }
                } label: {
                    if isRedeeming {
                        ProgressView()
                    } else {
                        Text("Redeem")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(redeemCode.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("\(appState.profile.referralCount)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.purple)
                Text("Friends Joined")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text("\(appState.profile.referralCount * 100)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.yellow)
                Text("Gold Earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            VStack(spacing: 4) {
                Text("\(appState.profile.handshakeCount)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.blue)
                Text("Handshakes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How It Works")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                referralStep(number: "1", text: "Share your referral code with friends")
                referralStep(number: "2", text: "They enter your code during sign-up")
                referralStep(number: "3", text: "You both earn 100 Gold when they complete their first verified quest")
                referralStep(number: "4", text: "Complete a group quest together for a 1.2x bonus")
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
    }

    private func referralStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.purple, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
