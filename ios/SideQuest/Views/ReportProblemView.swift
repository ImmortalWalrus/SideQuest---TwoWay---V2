import SwiftUI

nonisolated enum ReportCategory: String, CaseIterable, Identifiable, Sendable {
    case bug = "Bug Report"
    case questIssue = "Quest Issue"
    case moderation = "Moderation Concern"
    case account = "Account Problem"
    case suggestion = "Feature Suggestion"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bug: "ladybug.fill"
        case .questIssue: "scroll.fill"
        case .moderation: "shield.fill"
        case .account: "person.crop.circle.badge.exclamationmark.fill"
        case .suggestion: "lightbulb.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

struct ReportProblemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ReportCategory = .bug
    @State private var descriptionText: String = ""
    @State private var showConfirmation: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var submitFailed: Bool = false

    var body: some View {
        Form {
            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(ReportCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Description") {
                TextEditor(text: $descriptionText)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if descriptionText.isEmpty {
                            Text("Describe the issue in detail...")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("App Version", systemImage: "info.circle")
                        .font(.subheadline)
                    Text("SideQuest v1.0.0 (Build 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Device", systemImage: "iphone")
                        .font(.subheadline)
                    Text(UIDevice.current.model + " — iOS " + UIDevice.current.systemVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Device Info")
            } footer: {
                Text("This info helps us diagnose the issue faster.")
            }

            Section {
                Button {
                    isSubmitting = true
                    Task {
                        let metadata = [
                            "appVersion": "1.0.0",
                            "device": UIDevice.current.model,
                            "os": "iOS " + UIDevice.current.systemVersion
                        ]
                        isSubmitting = false
                        showConfirmation = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Label("Submit Report", systemImage: "paperplane.fill")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 || isSubmitting)
            }
        }
        .navigationTitle("Report a Problem")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Report Submitted", isPresented: $showConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("Thanks for your feedback! We'll review your report and get back to you if needed.")
        }
        .alert("Submission Failed", isPresented: $submitFailed) {
            Button("OK") {}
        } message: {
            Text("Unable to submit your report. Please check your connection and try again.")
        }
    }
}
