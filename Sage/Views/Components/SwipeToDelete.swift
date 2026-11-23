import SwiftUI

/// Swipe a row to the right to reveal a red Delete button on its left.
/// A long swipe (past about half the row) deletes straight away.
/// Tapping the row while it's open closes it.
struct SwipeToDelete<Content: View>: View {
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var rowWidth: CGFloat = 320

    private let revealWidth: CGFloat = 92
    private var fullSwipe: CGFloat { max(revealWidth + 60, rowWidth * 0.55) }
    private var pastFullSwipe: Bool { offset > fullSwipe }

    var body: some View {
        content
            .background(Theme.card)
            .offset(x: offset)
            .overlay {
                // While open, a tap on the row closes it instead of opening the entry.
                if offset > 0 {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { close() }
                }
            }
            .background(alignment: .leading) {
                // Delete button, revealed behind the row as it slides right.
                Button(role: .destructive) { commitDelete() } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.system(size: 17, weight: .semibold))
                        Text("Delete").font(.manrope(12, .bold))
                    }
                    .foregroundStyle(.white)
                    .opacity(offset > 30 ? 1 : 0)
                    .frame(width: max(offset, 0))
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
                    startOffset = offset
                }
                guard horizontal == true else { return }
                let next = startOffset + v.translation.width
                // Resist slightly beyond the full-swipe point; never past the left edge.
                offset = min(max(0, next), rowWidth)
            }
            .onEnded { v in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                let projected = startOffset + v.predictedEndTranslation.width
                if offset > fullSwipe || projected > rowWidth * 0.9 {
                    commitDelete()
                } else if offset > revealWidth / 2 || projected > revealWidth {
                    withAnimation(.spring(duration: 0.3)) { offset = revealWidth }
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(.spring(duration: 0.3)) { offset = 0 }
    }

    private func commitDelete() {
        withAnimation(.easeOut(duration: 0.2)) { offset = rowWidth }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeInOut(duration: 0.25)) { onDelete() }
        }
    }
}
