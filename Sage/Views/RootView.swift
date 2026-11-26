import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch app.tab {
                case .home: HomeView()
                case .day: DayView()
                case .week: WeekView()
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) { TabBar() }

            if let toast = app.toast {
                ToastView(message: toast)
                    .padding(.bottom, Theme.tabBarHeight + 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(Theme.text)
        .font(.manrope(15))
        .tint(Theme.accent)
        .sheet(item: $app.logRequest) { request in
            LogSheet(request: request)
                .presentationDetents([.large])
                .presentationCornerRadius(28)
                .presentationBackground(Theme.background)
        }
        .onOpenURL { url in
            if let payload = ClaudeImport.parse(url: url) {
                app.openImport(payload)
            } else {
                app.showToast("That link didn't contain any food")
            }
        }
        .task { app.checkClipboardForClaude() }
        .task { _ = await ProductDatabase.shared.prepare() }
        .task { await syncWeightIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.checkClipboardForClaude()
                Task { await syncWeightIfNeeded() }
            }
        }
    }

    private func syncWeightIfNeeded() async {
        if app.showsWorkouts { await health.loadWorkouts(on: DayKey.todayKey) }
        guard app.healthEnabled, app.readWeight else { return }
        if let last = app.lastSync, Date().timeIntervalSince(last) < 15 * 60 { return }
        await health.syncWeights(into: context)
        if health.lastError == nil { app.lastSync = .now }
    }
}

/// Fixed iOS tab bar: Home · Day · [+ Log] · Week · Profile.
struct TabBar: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home", "house", "house.fill")
            item(.day, "Day", "calendar", "calendar")
            Button { app.openLog() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
            .frame(maxWidth: .infinity)
            .offset(y: -6)
            .accessibilityLabel("Log food")
            item(.week, "Week", "chart.bar", "chart.bar.fill")
            item(.profile, "Profile", "person", "person.fill")
        }
        .frame(height: Theme.tabBarHeight)
        .padding(.top, 4)
        .background {
            Theme.card
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func item(_ tab: AppTab, _ title: String, _ icon: String, _ filledIcon: String) -> some View {
        let on = app.tab == tab
        return Button {
            if tab == .day && app.tab != .day { app.dayOffset = 0 }
            if tab == .week && app.tab != .week { app.weekOffset = 0 }
            app.tab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: on ? filledIcon : icon)
                    .font(.system(size: 19, weight: on ? .semibold : .regular))
                    .frame(height: 24)
                Text(title).font(.manrope(11, on ? .bold : .medium))
            }
            .foregroundStyle(on ? Theme.accent : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
