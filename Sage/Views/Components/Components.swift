import SwiftUI

/// Calorie ring: fills toward the goal, shows kcal left (or over) in the middle.
struct CalorieRing: View {
    var eaten: Double
    var goal: Double
    var size: CGFloat = 128
    var lineWidth: CGFloat = 12

    private var left: Double { goal - eaten }
    private var color: Color { left >= 0 ? Theme.accent : Theme.over }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: goal > 0 ? min(1, eaten / goal) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: eaten)
            VStack(spacing: 0) {
                Text(abs(left).kcalString)
                    .bigNumber(28)
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text(left >= 0 ? "kcal left" : "kcal over")
                    .font(.manrope(12, .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(abs(left).kcalString) kcal \(left >= 0 ? "left" : "over")")
    }
}

struct MacroBar: View {
    var name: String
    var value: Double
    var goal: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.manrope(13, .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                (Text(value.grams).font(.manrope(15, .bold)).foregroundColor(Theme.text)
                 + Text(" / \(goal.grams) g").font(.manrope(12, .medium)).foregroundColor(Theme.muted))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * (goal > 0 ? min(1, value / goal) : 0))
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(value.grams) of \(goal.grams) grams")
    }
}

/// Ring + protein/carbs/fat bars. Used on Home ("Today") and Day ("Summary").
struct SummaryCard: View {
    var title: String
    var totals: Macros
    var goals: Goals

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.manrope(17, .bold))
                Spacer()
                Text("\(totals.kcal.kcalString) of \(goals.kcal.kcalString) kcal")
                    .font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 18) {
                CalorieRing(eaten: totals.kcal, goal: goals.kcal)
                VStack(spacing: 14) {
                    MacroBar(name: "Protein", value: totals.p, goal: goals.p, color: Theme.accent)
                    MacroBar(name: "Carbs", value: totals.c, goal: goals.c, color: Theme.carbs)
                    MacroBar(name: "Fat", value: totals.f, goal: goals.f, color: Theme.fat)
                }
            }
        }
        .card()
    }
}

/// Large title block used at the top of each tab.
struct PageHeader<Trailing: View>: View {
    var eyebrow: String
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow).font(.manrope(13, .medium)).foregroundStyle(Theme.muted)
                Text(title).font(.manrope(30, .bold, relativeTo: .largeTitle)).tracking(-0.6)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            trailing
        }
        .frame(minHeight: 56, alignment: .bottom)
    }
}

/// Prev/next pair for Day and Week.
struct PrevNextButtons: View {
    var canGoNext: Bool
    var prevLabel: String
    var nextLabel: String
    var prev: () -> Void
    var next: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: prev) { Image(systemName: "chevron.left") }
                .buttonStyle(CircleIconButtonStyle())
                .accessibilityLabel(prevLabel)
            Button(action: next) { Image(systemName: "chevron.right") }
                .buttonStyle(CircleIconButtonStyle())
                .opacity(canGoNext ? 1 : 0.35)
                .disabled(!canGoNext)
                .accessibilityLabel(nextLabel)
        }
    }
}

/// Segmented pill toggle (1M/3M, list tabs, per-100g/per-serving).
struct PillPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var filled = false   // filled = green selected pill (weight range); otherwise white-on-track tabs

    var body: some View {
        HStack(spacing: filled ? 6 : 2) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let label = options[i].1
                let on = value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(label)
                        .font(.manrope(13, on ? .bold : .medium))
                        .foregroundStyle(filled && on ? Color.white : Theme.text)
                        .padding(.horizontal, 14)
                        .frame(minWidth: filled ? 48 : 0, maxWidth: filled ? nil : .infinity, minHeight: filled ? 34 : 36)
                        .background(
                            Capsule().fill(filled ? (on ? Theme.accent : Theme.chip) : (on ? Color.white : .clear))
                        )
                        .shadow(color: !filled && on ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(filled ? 0 : 3)
        .background(filled ? Color.clear : Theme.chip, in: Capsule())
    }
}

struct ToastView: View {
    var message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.softAccent)
            Text(message).font(.manrope(14, .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.text, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text).font(.manrope(17, .bold))
    }
}
