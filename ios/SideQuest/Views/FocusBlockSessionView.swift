import SwiftUI
import Combine
import UserNotifications
import CallKit

struct FocusBlockSessionView: View {
    let quest: Quest
    let instanceId: String
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var callMonitor = CallMonitor()
    @State private var sessionActive: Bool = false
    @State private var showRulesBriefing: Bool = true
    @State private var focusSeconds: TimeInterval = 0
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var startTime: Date?
    @State private var pauseCount: Int = 0
    @State private var totalPauseSeconds: TimeInterval = 0
    @State private var backgroundStart: Date?
    @State private var backgroundEvents: Int = 0
    @State private var longestBackground: TimeInterval = 0
    @State private var completedSession: FocusSession?
    @State private var showDQAlert: Bool = false
    @State private var dqReason: String = ""
    @State private var pulseGoal: Bool = false
    @State private var breathPhase: Double = 0
    @State private var isPaused: Bool = false
    @State private var showBackgroundWarning: Bool = false
    @State private var lastBackgroundDuration: TimeInterval = 0
    @State private var backgroundCountdownRemaining: TimeInterval = 0
    @State private var rulesAccepted: Bool = false
    @State private var activeFocusStart: Date?
    @State private var accumulatedFocus: TimeInterval = 0
    @State private var timerActive: Bool = false
    @State private var showFailedScreen: Bool = false
    @State private var healthBarProgress: Double = 1.0
    @State private var failedDismissing: Bool = false
    @State private var callExemptBackground: Bool = false


    private let tickPublisher = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let breathPublisher = Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()

    private var targetDuration: TimeInterval { Double((quest.targetFocusMinutes ?? 10) * 60) }
    private var maxPauses: Int { quest.maxPauseCount ?? 0 }
    private var maxPauseSecs: Int { quest.maxTotalPauseSeconds ?? 0 }
    private var pathColor: Color { PathColorHelper.color(for: quest.path) }
    private var goalReached: Bool { focusSeconds >= targetDuration }
    private var progress: Double { min(1.0, focusSeconds / max(1, targetDuration)) }

    private var allowedBackgroundSeconds: Int {
        if maxPauseSecs > 0 {
            return maxPauseSecs
        }
        if maxPauses > 0 {
            return 60
        }
        return 10
    }

    private var perExitGraceSeconds: Int {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return 10
        }
        if maxPauseSecs > 0 {
            return min(60, maxPauseSecs)
        }
        return 30
    }

    var body: some View {
        NavigationStack {
            if showFailedScreen {
                failedScreen
            } else if let session = completedSession {
                FocusSummaryView(
                    session: session,
                    quest: quest,
                    onSubmit: {
                        appState.submitFocusEvidence(for: instanceId, session: session)
                        dismiss()
                    },
                    onDiscard: { dismiss() }
                )
            } else if showRulesBriefing && !sessionActive {
                rulesBriefingScreen
            } else {
                mainContent
            }
        }
        .interactiveDismissDisabled(sessionActive || showRulesBriefing || showFailedScreen)
    }

    // MARK: - Rules Briefing Screen

    private var rulesBriefingScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    .black, .black, .black,
                    Color.cyan.opacity(0.15), .black, Color.cyan.opacity(0.1),
                    .black, Color.cyan.opacity(0.08), .black
                ]
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Circle()
                            .stroke(Color.cyan.opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundStyle(.cyan)
                    }

                    VStack(spacing: 8) {
                        Text("FOCUS LOCK")
                            .font(.title.weight(.black))
                            .foregroundStyle(.white)
                            .tracking(3)
                        Text(formatDuration(targetDuration) + " Session")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                }

                Spacer()
                    .frame(height: 40)

                VStack(alignment: .leading, spacing: 0) {
                    ruleRow(
                        icon: "battery.100.bolt",
                        iconColor: .green,
                        title: "Plug in your phone",
                        subtitle: "Keep your device charging and screen on"
                    )
                    ruleDivider
                    ruleRow(
                        icon: "iphone.gen3.slash",
                        iconColor: .orange,
                        title: "Do not leave the app",
                        subtitle: exitRuleDescription
                    )
                    ruleDivider
                    ruleRow(
                        icon: "phone.fill",
                        iconColor: .green,
                        title: "Calls are allowed",
                        subtitle: "Phone & FaceTime calls won\'t count against you"
                    )
                    ruleDivider
                    ruleRow(
                        icon: "timer",
                        iconColor: .cyan,
                        title: "Timer tracks active time only",
                        subtitle: "Clock pauses if you leave, but penalties still apply"
                    )
                    ruleDivider
                    ruleRow(
                        icon: pauseRuleIcon,
                        iconColor: pauseRuleColor,
                        title: pauseRuleTitle,
                        subtitle: pauseRuleSubtitle
                    )
                }
                .padding(16)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                .padding(.horizontal, 20)

                Spacer()
                    .frame(height: 16)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.subheadline)
                    Text("You have **\(perExitGraceSeconds) seconds** if you leave the app before the challenge is lost.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .multilineTextAlignment(.leading)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.4)) {
                            showRulesBriefing = false
                        }
                        startSession()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lock.open.fill")
                            Text("I Understand — Begin Focus")
                        }
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func ruleRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.vertical, 14)
    }

    private var ruleDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 46)
    }

    private var exitRuleDescription: String {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return "You have 10 seconds before disqualification"
        }
        if maxPauseSecs > 0 && maxPauses > 0 {
            return "Max \(maxPauses) exit(s), \(maxPauseSecs)s total allowed"
        }
        if maxPauseSecs > 0 {
            return "\(maxPauseSecs)s total out-of-app time allowed"
        }
        if maxPauses > 0 {
            return "Max \(maxPauses) exit(s) allowed"
        }
        return "Stay inside the app the entire duration"
    }

    private var pauseRuleIcon: String {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return "nosign"
        }
        return "pause.circle"
    }

    private var pauseRuleColor: Color {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return .red
        }
        return .yellow
    }

    private var pauseRuleTitle: String {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return "No pausing permitted"
        }
        return "Limited pauses allowed"
    }

    private var pauseRuleSubtitle: String {
        if maxPauses == 0 && maxPauseSecs == 0 {
            return "Any interruption beyond 10 seconds = disqualification"
        }
        var parts: [String] = []
        if maxPauses > 0 { parts.append("\(maxPauses) pause(s)") }
        if maxPauseSecs > 0 { parts.append("\(maxPauseSecs)s total") }
        return "Allowed: " + parts.joined(separator: ", ")
    }

    // MARK: - Main Session Content

    private var mainContent: some View {
        ZStack {
            focusBackground
            uiOverlay

            if showBackgroundWarning {
                backgroundWarningOverlay
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard sessionActive else { return }
            if newPhase == .background || newPhase == .inactive {
                if backgroundStart == nil {
                    if let focusStart = activeFocusStart {
                        accumulatedFocus += Date().timeIntervalSince(focusStart)
                    }
                    activeFocusStart = nil
                    backgroundStart = Date()
                    callExemptBackground = callMonitor.isOnCall
                    if !callExemptBackground {
                        backgroundEvents += 1
                        NotificationService.shared.scheduleFocusBlockWarning(graceSeconds: perExitGraceSeconds)
                    }
                }
            } else if newPhase == .active, let bgStart = backgroundStart {
                let duration = Date().timeIntervalSince(bgStart)
                backgroundStart = nil
                activeFocusStart = Date()
                NotificationService.shared.cancelFocusBlockNotifications()
                longestBackground = max(longestBackground, duration)
                lastBackgroundDuration = duration

                if callExemptBackground {
                    callExemptBackground = false
                    return
                }

                totalPauseSeconds += duration
                pauseCount += 1

                let graceLimit = Double(perExitGraceSeconds)

                if duration > graceLimit {
                    if maxPauses == 0 && maxPauseSecs == 0 {
                        dqReason = "You left the app for \(Int(duration))s. Maximum allowed: \(perExitGraceSeconds)s."
                        showDQAlert = true
                    } else if maxPauses > 0 && pauseCount > maxPauses {
                        dqReason = "Too many exits (\(pauseCount)/\(maxPauses) allowed)."
                        showDQAlert = true
                    } else if maxPauseSecs > 0 && totalPauseSeconds > Double(maxPauseSecs) {
                        dqReason = "Total out-of-app time exceeded (\(Int(totalPauseSeconds))s/\(maxPauseSecs)s allowed)."
                        showDQAlert = true
                    } else {
                        showReturnWarning(duration: duration)
                    }
                } else if duration > 3 {
                    if maxPauses == 0 && maxPauseSecs == 0 {
                        showReturnWarning(duration: duration)
                    } else {
                        if maxPauses > 0 && pauseCount > maxPauses {
                            dqReason = "Too many exits (\(pauseCount)/\(maxPauses) allowed)."
                            showDQAlert = true
                        } else if maxPauseSecs > 0 && totalPauseSeconds > Double(maxPauseSecs) {
                            dqReason = "Total out-of-app time exceeded (\(Int(totalPauseSeconds))s/\(maxPauseSecs)s allowed)."
                            showDQAlert = true
                        } else {
                            showReturnWarning(duration: duration)
                        }
                    }
                }
            }
        }
        .onDisappear {
            timerActive = false
        }
        .onReceive(tickPublisher) { _ in
            guard timerActive, sessionActive, let start = startTime else { return }
            elapsedSeconds = Date().timeIntervalSince(start)
            if backgroundStart == nil {
                if let focusStart = activeFocusStart {
                    focusSeconds = accumulatedFocus + Date().timeIntervalSince(focusStart)
                }
                isPaused = false
            } else {
                isPaused = true
            }
            if goalReached && !pulseGoal {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseGoal = true
                }
            }
        }
        .onReceive(breathPublisher) { _ in
            guard timerActive, sessionActive else { return }
            withAnimation(.easeInOut(duration: 5.0)) {
                breathPhase = breathPhase == 0 ? 1 : 0
            }
        }
        .sensoryFeedback(.success, trigger: goalReached)
        .alert("Challenge Failed", isPresented: $showDQAlert) {
            Button("OK") { triggerFailure() }
        } message: { Text(dqReason) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessionActive {
                    Button("Close") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if sessionActive {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.cyan.opacity(0.6))
                        Text(formatDuration(elapsedSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Background Warning Overlay

    private var backgroundWarningOverlay: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)

                Text("You Left The App!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Text("Gone for \(Int(lastBackgroundDuration))s")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(lastBackgroundDuration > Double(perExitGraceSeconds / 2) ? .orange : .yellow)

                if maxPauses == 0 && maxPauseSecs == 0 {
                    remainingGraceView(used: lastBackgroundDuration, total: Double(perExitGraceSeconds))
                } else {
                    VStack(spacing: 8) {
                        if maxPauses > 0 {
                            HStack {
                                Text("Exits used")
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(pauseCount) / \(maxPauses)")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(pauseCount >= maxPauses ? .red : .white)
                            }
                        }
                        if maxPauseSecs > 0 {
                            HStack {
                                Text("Time away")
                                    .foregroundStyle(.white.opacity(0.6))
                                Spacer()
                                Text("\(Int(totalPauseSeconds))s / \(maxPauseSecs)s")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(totalPauseSeconds > Double(maxPauseSecs) * 0.8 ? .red : .white)
                            }
                        }
                    }
                    .font(.subheadline)
                    .padding(16)
                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
                }

                Text("Don't leave again or you risk disqualification.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showBackgroundWarning = false
                    }
                } label: {
                    Text("Continue Focus")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding(32)
            .frame(maxWidth: 340)
        }
        .transition(.opacity)
    }

    private func remainingGraceView(used: Double, total: Double) -> some View {
        VStack(spacing: 8) {
            let remaining = max(0, total - used)
            HStack {
                Text("Grace remaining")
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(remaining))s / \(Int(total))s")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(remaining < 4 ? .red : .white)
            }
            .font(.subheadline)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(remaining < 4 ? Color.red.gradient : Color.cyan.gradient)
                        .frame(width: geo.size.width * (remaining / total))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func showReturnWarning(duration: TimeInterval) {
        lastBackgroundDuration = duration
        withAnimation(.spring(response: 0.3)) {
            showBackgroundWarning = true
        }
    }

    // MARK: - Failed Screen

    private var failedScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5, 0.5], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: [
                    .black, .black, .black,
                    Color.red.opacity(0.15), .black, Color.red.opacity(0.1),
                    .black, Color.red.opacity(0.08), .black
                ]
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 100, height: 100)
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 2)
                            .frame(width: 100, height: 100)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                    }

                    VStack(spacing: 8) {
                        Text("CHALLENGE FAILED")
                            .font(.title.weight(.black))
                            .foregroundStyle(.red)
                            .tracking(3)
                        Text(quest.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()
                    .frame(height: 48)

                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text("HP")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(healthBarProgress > 0 ? "DEPLETING" : "DESTROYED")
                            .font(.caption.weight(.black))
                            .foregroundStyle(healthBarProgress > 0 ? .orange : .red)
                            .tracking(1)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.08))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: healthBarProgress > 0.3
                                            ? [.green, .yellow]
                                            : healthBarProgress > 0
                                                ? [.orange, .red]
                                                : [.red.opacity(0.3)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * healthBarProgress)
                                .animation(.easeOut(duration: 2.0), value: healthBarProgress)
                        }
                    }
                    .frame(height: 16)
                }
                .padding(20)
                .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 16))
                .padding(.horizontal, 20)

                Spacer()
                    .frame(height: 20)

                if !dqReason.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.subheadline)
                        Text(dqReason)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.leading)
                }

                Spacer()

                if failedDismissing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                        Text("Returning to Quick Tab...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.bottom, 60)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startHealthBarDepletion()
        }
        .sensoryFeedback(.error, trigger: showFailedScreen)
    }

    private func triggerFailure() {
        sessionActive = false
        timerActive = false
        NotificationService.shared.cancelFocusBlockNotifications()
        appState.failQuest(instanceId)
        withAnimation(.spring(response: 0.4)) {
            showFailedScreen = true
        }
    }

    private func startHealthBarDepletion() {
        withAnimation(.easeOut(duration: 2.0).delay(0.5)) {
            healthBarProgress = 0.0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            failedDismissing = true
            try? await Task.sleep(for: .seconds(1.5))
            appState.selectedTab = 0
            dismiss()
        }
    }

    // MARK: - Focus Background

    private var focusBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if sessionActive {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                (goalReached ? Color.green : isPaused ? Color.orange : Color.cyan).opacity(0.25),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .scaleEffect(0.8 + breathPhase * 0.3)
                    .animation(.easeInOut(duration: 5), value: breathPhase)

                Circle()
                    .stroke(
                        (goalReached ? Color.green : Color.cyan).opacity(0.1),
                        lineWidth: 1
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(0.9 + breathPhase * 0.15)
                    .animation(.easeInOut(duration: 5).delay(0.5), value: breathPhase)
            }
        }
    }

    // MARK: - UI Overlay

    private var uiOverlay: some View {
        VStack {
            if sessionActive {
                activeHUD
            }
            Spacer()
            controlPanel
        }
    }

    private var activeHUD: some View {
        VStack(spacing: 12) {
            Text(formatDuration(focusSeconds))
                .font(.system(size: 72, weight: .thin, design: .rounded))
                .foregroundStyle(goalReached ? .green : .white)
                .contentTransition(.numericText())
                .animation(.linear(duration: 0.3), value: focusSeconds)

            Text("of \(formatDuration(targetDuration))")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))

            if goalReached {
                Label("Goal Reached!", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .scaleEffect(pulseGoal ? 1.05 : 1.0)
                    .transition(.scale.combined(with: .opacity))
            } else if callMonitor.isOnCall && isPaused {
                Label("On Call — Timer Paused", systemImage: "phone.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.4), lineWidth: 1))
                    .transition(.scale.combined(with: .opacity))
            } else if isPaused {
                Label("Paused — Return to app", systemImage: "pause.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("Focusing...")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.6), in: Capsule())
            }

            if maxPauses > 0 || maxPauseSecs > 0 {
                HStack(spacing: 16) {
                    if maxPauses > 0 {
                        VStack(spacing: 2) {
                            Text("\(pauseCount)/\(maxPauses)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(pauseCount >= maxPauses ? .red : .white)
                            Text("Exits")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if maxPauseSecs > 0 {
                        VStack(spacing: 2) {
                            Text("\(Int(totalPauseSeconds))/\(maxPauseSecs)s")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(totalPauseSeconds >= Double(maxPauseSecs) ? .red : .white)
                            Text("Away Time")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 100)
        .animation(.spring(response: 0.4), value: goalReached)
        .animation(.spring(response: 0.4), value: isPaused)
    }

    private var controlPanel: some View {
        VStack(spacing: 16) {
            if sessionActive {
                VStack(spacing: 6) {
                    HStack {
                        Text(formatDuration(focusSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Spacer()
                        Text(formatDuration(targetDuration))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(goalReached ? Color.green.gradient : Color.cyan.gradient)
                                .frame(width: geo.size.width * progress)
                                .animation(.linear(duration: 0.5), value: progress)
                        }
                    }
                    .frame(height: 8)
                }

                HStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.title3)
                            .foregroundStyle(.cyan)
                        Text("LOCKED")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 36)
                    VStack(spacing: 4) {
                        Text("\(pauseCount)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(pauseCount > 0 ? .orange : .green)
                        Text("EXITS")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    Divider().frame(height: 36)
                    VStack(spacing: 4) {
                        Text("\(Int(totalPauseSeconds))s")
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(totalPauseSeconds > 0 ? .orange : .green)
                        Text("AWAY")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    endSession()
                } label: {
                    Label(
                        goalReached ? "Finish" : "End Session",
                        systemImage: goalReached ? "checkmark.circle.fill" : "stop.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(goalReached ? .green : .secondary)
                .scaleEffect(pulseGoal && goalReached ? 1.03 : 1.0)
            }
        }
        .padding(20)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Session Logic

    private func startSession() {
        sessionActive = true
        focusSeconds = 0
        elapsedSeconds = 0
        accumulatedFocus = 0
        let now = Date()
        startTime = now
        activeFocusStart = now
        pauseCount = 0
        totalPauseSeconds = 0
        backgroundStart = nil
        backgroundEvents = 0
        longestBackground = 0
        isPaused = false
        dqReason = ""
        showBackgroundWarning = false
        timerActive = true
        if targetDuration >= 1800 {
            NotificationService.shared.scheduleFocusMilestoneWarnings(remainingSeconds: targetDuration)
        }
    }

    private func endSession() {
        sessionActive = false
        timerActive = false
        NotificationService.shared.cancelFocusBlockNotifications()

        var flags: [FocusIntegrityFlag] = []

        if backgroundEvents > 0 && maxPauses == 0 && maxPauseSecs == 0 {
            flags.append(.appBackgrounded)
        }
        if maxPauses > 0 && pauseCount > maxPauses {
            flags.append(.tooManyPauses)
        }
        if maxPauseSecs > 0 && totalPauseSeconds > Double(maxPauseSecs) {
            flags.append(.totalPauseExceeded)
        }
        if focusSeconds < 60 {
            flags.append(.tooShort)
        }

        let session = FocusSession(
            id: UUID().uuidString,
            startedAt: startTime,
            endedAt: Date(),
            focusDurationSeconds: focusSeconds,
            targetDurationSeconds: targetDuration,
            pauseCount: pauseCount,
            totalPauseSeconds: totalPauseSeconds,
            maxAllowedPauseCount: maxPauses,
            maxAllowedPauseSeconds: maxPauseSecs,
            backgroundEvents: backgroundEvents,
            longestBackgroundSeconds: longestBackground,
            integrityFlags: flags,
            wasDisqualified: !dqReason.isEmpty
        )

        withAnimation(.spring(response: 0.4)) {
            completedSession = session
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
