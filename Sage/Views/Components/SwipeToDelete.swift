import SwiftUI

/// Swipe a row to the left to reveal a red Delete button on its right.
/// A long swipe (past about half the row) deletes straight away.
/// Tapping the row while it's open closes it.
struct SwipeToDelete<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    /// How far the row has slid left (always ≥ 0).
    @State private var reveal: CGFloat = 0
    @State private var startReveal: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var rowWidth: CGFloat = 320

    private let buttonWidth: CGFloat = 92
    private var fullSwipe: CGFloat { max(buttonWidth + 60, rowWidth * 0.55) }
    private var pastFullSwipe: Bool { reveal > fullSwipe }

    var body: some View {
        content
            .background(Theme.card)
            .offset(x: -reveal)
            .overlay {
                // While open, a tap on the row closes it instead of opening the entry.
                if reveal > 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: -reveal)
                        .onTapGesture { close() }
                }
            }
            .background(alignment: .trailing) {
                // Delete button, revealed behind the row as it slides left.
                Button(role: .destructive) { commitDelete() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.system(size: 17, weight: .semibold))
                        Text("Delete").font(.manrope(12, .bold))
                    }
                    .foregroundStyle(.white)
                    .opacity(reveal > 30 ? 1 : 0)
                    .frame(width: reveal)
                    .frame(maxHeight: .infinity)
                    .background(Theme.danger)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { rowWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in rowWidth = w }
            })
            .clipped()
            .simultaneousGesture(drag)
            .sensoryFeedback(.impact(weight: .medium), trigger: pastFullSwipe) { _, new in new }
            .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                // Decide once per drag whether it's a sideways swipe or a scroll.
                if horizontal == nil {
                    horizontal = abs(v.translation.width) > abs(v.translation.height) * 1.2
                    startReveal = reveal
                }
                guard horizontal == true else { return }
                reveal = min(max(0, startReveal - v.translation.width), rowWidth)
            }
            .onEnded { v in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let projected = startReveal - v.predictedEndTranslation.width
                if reveal > fullSwipe || projected > rowWidth * 0.9 {
                    commitDelete()
                } else if reveal > buttonWidth / 2 || projected > buttonWidth {
                    withAnimation(.spring(duration: 0.3)) { reveal = buttonWidth }
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(.spring(duration: 0.3)) { reveal = 0 }
    }

    private func commitDelete() {
        withAnimation(.easeOut(duration: 0.2)) { reveal = rowWidth }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeInOut(duration: 0.25)) { onDelete() }
        }
    }
}
