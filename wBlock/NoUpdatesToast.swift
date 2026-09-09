import SwiftUI

/// Non-blocking result of a manual update check on either platform.
struct NoUpdatesToast: View {
    let dismiss: () -> Void
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.8)))
    private var dragOffset: CGSize = .zero

    static func shouldDismissDrag(_ translation: CGSize, predicted: CGSize) -> Bool {
        abs(translation.width) >= 44 || translation.height <= -44
            || abs(predicted.width) >= 120 || predicted.height <= -120
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("No Updates Found")
                    .font(.subheadline.weight(.semibold))
                Text("You're already using the latest filters.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        #if os(macOS)
        .frame(maxWidth: 440)
        #endif
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .offset(dragOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, offset, _ in
                    offset = CGSize(width: value.translation.width, height: min(0, value.translation.height))
                }
                .onEnded { value in
                    if Self.shouldDismissDrag(value.translation, predicted: value.predictedEndTranslation) {
                        dismiss()
                    }
                }
        )
        .onTapGesture(perform: dismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, dismiss)
        .accessibilityAction(.escape, dismiss)
        .task {
            do { try await Task.sleep(nanoseconds: 8_000_000_000) } catch { return }
            dismiss()
        }
    }
}
