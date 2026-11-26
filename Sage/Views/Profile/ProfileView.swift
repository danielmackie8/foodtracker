import SwiftUI
import SwiftData
import UIKit

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
                    GoalRow(name: "Steps", value: $app.stepGoal, step: 500, unit: "")
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

                LogWithClaudeCard()

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

/// How to log food Claude estimates: set-up text to copy into a Claude project.
private struct LogWithClaudeCard: View {
    @Environment(AppState.self) private var app
    @State private var showSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Log with Claude").font(.manrope(17, .bold))
            }
            Text("Tell Claude what you ate and tap Copy on the code block in its reply. When you switch back to Sage, the estimate opens ready to add.")
                .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: Binding(get: { app.autoClaudePaste }, set: { app.autoClaudePaste = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open copied estimates automatically").font(.manrope(14, .semibold))
                    Text("To skip iOS's Allow Paste prompt: Settings › Apps › Sage › Paste from Other Apps › Allow")
                        .font(.manrope(12, .medium)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.switchOn)
            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = ClaudeImport.claudeInstructions
                    app.showToast("Instructions copied")
                } label: {
                    Label("Copy instructions", systemImage: "doc.on.doc")
                        .font(.manrope(14, .bold))
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                Button { withAnimation(.snappy) { showSteps.toggle() } } label: {
                    Text(showSteps ? "Hide set-up" : "How to set up")
                        .font(.manrope(14, .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTouch)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            if showSteps {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array([
                        "Tap Copy instructions.",
                        "In the Claude app, create a project called Sage and paste them into its instructions.",
                        "Start chats about food in that project, e.g. “Wagamama chicken katsu curry for dinner”.",
                        "Tap Copy on the code block in Claude’s reply, then switch to Sage. (Or tap + › From Claude.)",
                    ].enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1).").font(.manrope(13, .bold)).foregroundStyle(Theme.accent)
                            Text(step).font(.manrope(13, .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .card()
    }
}
