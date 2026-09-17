import SwiftUI

#if os(iOS)
/// Teaches the hidden row gestures once. Rows on iOS keep their secondary
/// actions behind a trailing swipe and a long press, and nothing on the row
/// itself says so. The first visit to a tab slides the top row aside for a
/// beat to show the swipe, and a card under the list explains both gestures
/// until the user dismisses it or performs either one.
@MainActor
enum RowGestureHint {
    static let storageKey = "rowGestureHintDismissed"
    /// Once per launch, so switching tabs does not replay the peek.
    static var hasPeeked = false

    static var isDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    /// Retire the hint once the user has performed either gesture themselves.
    static func markLearned() {
        guard !isDismissed else { return }
        withAnimation(.easeOut(duration: 0.25)) { isDismissed = true }
    }
}

struct RowGestureHintCard: View {
    @AppStorage(RowGestureHint.storageKey) private var dismissed = false

    var body: some View {
        if !dismissed {
            HStack(spacing: 12) {
                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Swipe a row for settings")
                        .font(.subheadline.weight(.semibold))
                    Text("Hold a row to move or delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeOut(duration: 0.25)) { dismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, -12)
            .accessibilityElement(children: .combine)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

/// Slides the first row aside once so the trailing swipe action shows for a
/// beat, the way Mail teaches its swipes. Runs only while the hint card is
/// still up, and only once per launch so a tab switch does not replay it.
/// The gear rides in from the trailing edge in step with the row, so it is
/// never visible while the row is at rest.
private struct RowGesturePeek: ViewModifier {
    static let reveal: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            // Trim what slides past the leading card edge without trimming
            // the switch, whose drawing overhangs its layout frame.
            .mask(Rectangle().padding(.trailing, -8))
            .listRowBackground(
                ZStack {
                    Color(UIColor.secondarySystemGroupedBackground)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: Self.reveal)
                            .frame(maxHeight: .infinity)
                            .background(Color.gray)
                            .offset(x: Self.reveal + offset)
                    }
                }
                .clipped()
            )
            .onAppear {
                guard !RowGestureHint.isDismissed, !RowGestureHint.hasPeeked, !reduceMotion else { return }
                RowGestureHint.hasPeeked = true
                // Wait for the list to land before moving anything.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    guard !RowGestureHint.isDismissed else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { offset = -Self.reveal }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { offset = 0 }
                    }
                }
            }
    }
}

extension View {
    /// Apply to the first row of the first section on iOS.
    func rowGesturePeek(_ isFirstRow: Bool) -> some View {
        modifier(RowGesturePeekIfNeeded(isFirstRow: isFirstRow))
    }
}

private struct RowGesturePeekIfNeeded: ViewModifier {
    let isFirstRow: Bool
    @AppStorage(RowGestureHint.storageKey) private var dismissed = false
    func body(content: Content) -> some View {
        if isFirstRow, !dismissed {
            content.modifier(RowGesturePeek())
        } else {
            content
        }
    }
}
#endif
