import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @State private var showShopFromReward: Bool = false
    @State private var visitedTabs: Set<Int> = [0]
    private var shouldShowInitialOnboarding: Bool {
        !appState.hasOnboarded
    }

    var body: some View {
        ZStack {
            if shouldShowInitialOnboarding {
                OnboardingView(appState: appState)
            } else {
                mainTabView
            }

            if appState.showRewardOverlay, let reward = appState.pendingRewards.first {
                RewardOverlayView(
                    reward: reward,
                    hasMore: appState.pendingRewards.count > 1,
                    onNext: { appState.dismissReward() },
                    onDone: { appState.dismissReward() },
                    onShop: {
                        appState.dismissReward()
                        showShopFromReward = true
                    }
                )
                .transition(.opacity)
                .zIndex(100)
            }

            if appState.showLevelUp {
                LevelUpOverlayView(level: appState.newLevelReached) {
                    appState.showLevelUp = false
                }
                .transition(.opacity)
                .zIndex(101)
            }

            VStack {
                if let toast = appState.currentToast {
                    ToastOverlayView(toast: toast) {
                        appState.dismissCurrentToast()
                    }
                }

                Spacer()
            }
            .zIndex(200)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: appState.currentToast)
        }
        .animation(.spring(response: 0.4), value: appState.isAuthenticated)
        .animation(.spring(response: 0.4), value: appState.hasOnboarded)
        .animation(.easeInOut(duration: 0.3), value: appState.showRewardOverlay)
        .sheet(isPresented: $showShopFromReward) {
            ShopView(appState: appState)
        }
        .onChange(of: appState.deepLinkDestination) { _, newValue in
            guard let destination = newValue else { return }
            appState.deepLinkDestination = nil
            handleDeepLink(destination)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appState.refreshSolarTimes()
            appState.startTimeIntegrity()
            appState.requestNotificationPermissionIfNeeded()
            appState.requestCameraAndMicIfNeeded()
            appState.checkOnboardingStaleness()
        }
        .fullScreenCover(isPresented: $appState.showOnboardingRefresh) {
            OnboardingView(appState: appState, isRefresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { output in
            guard let userInfo = output.userInfo,
                  let type = userInfo["type"] as? String,
                  let deepLinkId = userInfo["deepLinkId"] as? String else { return }
            appState.handlePushNotificationTap(type: type, deepLinkId: deepLinkId)
        }
        .onChange(of: appState.solarService.isReady) { _, ready in
            if ready {
                appState.applySolarTimeWindows()
            }
        }
    }

    private var mainTabView: some View {
        VStack(spacing: 0) {
            ZStack {
                QuickTabView(appState: appState)
                    .opacity(appState.selectedTab == 0 ? 1 : 0)
                    .allowsHitTesting(appState.selectedTab == 0)
                if visitedTabs.contains(1) {
                    QuestsTabView(appState: appState)
                        .opacity(appState.selectedTab == 1 ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == 1)
                }
                if visitedTabs.contains(2) {
                    MapExploreView(appState: appState)
                        .opacity(appState.selectedTab == 2 ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == 2)
                }
                if visitedTabs.contains(3) {
                    ProfileTabView(appState: appState)
                        .opacity(appState.selectedTab == 3 ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == 3)
                }
                if visitedTabs.contains(4) {
                    DevModeView(appState: appState)
                        .opacity(appState.selectedTab == 4 ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == 4)
                }
            }
            .frame(maxHeight: .infinity)
            .onChange(of: appState.selectedTab) { _, newTab in
                visitedTabs.insert(newTab)
            }

            if !appState.isImmersive {
                customTabBar
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: appState.isImmersive)
        .ignoresSafeArea(.keyboard)
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItem(icon: "bolt.fill", label: "Quick", tab: 0)
            tabItem(icon: "scroll.fill", label: "Quests", tab: 1)
            tabItem(icon: "map.fill", label: "Explore", tab: 2)
            tabItem(icon: "person.crop.circle.fill", label: "Profile", tab: 3)
            tabItem(icon: "wrench.and.screwdriver.fill", label: "Dev", tab: 4)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator)
                .frame(height: 0.5)
        }
    }

    private func tabItem(icon: String, label: String, tab: Int) -> some View {
        Button {
            appState.selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.monochrome)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(appState.selectedTab == tab ? .blue : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: appState.selectedTab)
    }

    private func handleDeepLink(_ destination: DeepLinkDestination) {
    }
}
