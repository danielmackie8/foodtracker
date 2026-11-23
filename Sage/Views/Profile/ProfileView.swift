import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(HealthKitManager.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var app = app
        ScrollView {
            VStack(spacing: Theme.gap) {
                PageHeader(eyebrow: "Settings", title: "Profile") { EmptyView() }

                // Apple Health
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(hex: 0xFF2D55), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health").font(.manrope(16, .bold))
                            Text(app.healthEnabled ? "Connected · last sync \(app.syncAgoLabel)" : "Not connected")
                                .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Toggle("Apple Health", isOn: Binding(
                            get: { app.healthEnabled },
                            set: { on in
                                if on {
                                    Task { await health.connect(app: app, context: context) }
                                } else {
                                    app.healthEnabled = false
                                    app.showToast("Apple Health disconnected")
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(Theme.switchOn)
                    }
                    .padding(16)

                    if app.healthEnabled {
                        Divider().overlay(Theme.border)
                        PermissionRow(name: "Weight", mode: "Read", isOn: $app.readWeight)
                        Divider().overlay(Theme.border).padding(.leading, 16)
                        PermissionRow(name: "Steps", mode: "Read", isOn: $app.readSteps)
                        Divider().overlay(Theme.border).padding(.leading, 16)
                        PermissionRow(name: "Workouts", mode: "Read", isOn: $app.readWorkouts)
                        Divider().overlay(Theme.border).padding(.leading, 16)
                        PermissionRow(name: "Dietary energy, protein, carbs, fat", mode: "Write", isOn: $app.writeNutrition)
                        Divider().overlay(Theme.border)
                        Button {
                            if let url = URL(string: "x-apple-health://") { openURL(url) }
                        } label: {
                            Text("Manage access in the Health app")
                                .font(.manrope(13, .semibold)).foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))

                // Goals
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily goals").font(.manrope(17, .bold)).padding(.bottom, 6)
                    GoalRow(name: "Calories", value: $app.goals.kcal, step: 50, unit: " kcal")
                    GoalRow(name: "Protein", value: $app.goals.p, step: 5, unit: " g")
                    GoalRow(name: "Carbs", value: $app.goals.c, step: 5, unit: " g")
                    GoalRow(name: "Fat", value: $app.goals.f, step: 5, unit: " g")
                    Divider().overlay(Theme.border).padding(.vertical, 6)
                    Toggle(isOn: $app.addWorkoutCalories) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add workout calories").font(.manrope(15, .semibold))
                            Text("Calories burnt in workouts raise that day's budget")
                                .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.switchOn)
                    .frame(minHeight: 52)
                }
                .card()

                Text("Product data from Open Food Facts, available under the Open Database Licence (ODbL).")
                    .font(.manrope(12)).foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct PermissionRow: View {
    var name: String
    var mode: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.manrope(14, .semibold))
                Text(mode).font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.switchOn)
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }
}

private struct GoalRow: View {
    var name: String
    @Binding var value: Double
    var step: Double
    var unit: String

    var body: some View {
        HStack(spacing: 10) {
            Text(name).font(.manrope(15, .semibold))
            Spacer()
            Button("−") { value = max(step, value - step) }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Lower \(name)")
            Text(value.kcalString + unit)
                .font(.manrope(16, .bold)).monospacedDigit()
                .frame(minWidth: 92)
                .contentTransition(.numericText())
            Button("+") { value += step }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel("Raise \(name)")
        }
        .frame(minHeight: 52)
        .sensoryFeedback(.selection, trigger: value)
    }
}
