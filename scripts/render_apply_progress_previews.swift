import AppKit
import SwiftUI

@main
struct ApplyProgressPreviewRenderer {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let converting = convertingPresentation()
        let outDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/media/img", isDirectory: true)

        write(
            macSheet(converting),
            size: CGSize(width: 500, height: 318),
            appearance: .aqua,
            to: outDir.appendingPathComponent("apply_progress_light.png")
        )
        write(
            macSheet(converting),
            size: CGSize(width: 500, height: 318),
            appearance: .darkAqua,
            to: outDir.appendingPathComponent("apply_progress_dark.png")
        )
        write(
            iosSheet(converting),
            size: CGSize(width: 390, height: 430),
            appearance: .aqua,
            to: outDir.appendingPathComponent("apply_progress_ios_light.png")
        )
        write(
            iosSheet(converting),
            size: CGSize(width: 390, height: 430),
            appearance: .darkAqua,
            to: outDir.appendingPathComponent("apply_progress_ios_dark.png")
        )
        print("wrote previews to \(outDir.path)")
    }

    @MainActor
    private static func convertingPresentation() -> ApplyProgressPresentation {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateFilterUpdatesFound(3)
        viewModel.updateScriptsUpdateResult(updated: 2, failed: 0)
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updatePhaseCompletion(reading: true, converting: false)
        viewModel.updateConvertingDone(2)
        viewModel.updateCurrentFilter("Privacy")
        return ApplyProgressPresentation.make(from: viewModel.state)
    }

    private static func macSheet(_ presentation: ApplyProgressPresentation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apply Changes")
                .font(.title2.weight(.semibold))
            ApplyProgressField(presentation: presentation)
        }
        .padding(20)
        .frame(width: 500, height: 318, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func iosSheet(_ presentation: ApplyProgressPresentation) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 16) {
                Text("Apply Changes")
                    .font(.title2.weight(.semibold))
                ApplyProgressField(presentation: presentation, groupedRows: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)

            Spacer(minLength: 0)
        }
        .frame(width: 390, height: 430, alignment: .top)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private static func write<V: View>(
        _ view: V,
        size: CGSize,
        appearance: NSAppearance.Name,
        to url: URL
    ) {
        let hosting = NSHostingView(
            rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
        )
        hosting.appearance = NSAppearance(named: appearance)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("FAIL: could not create bitmap for \(url.lastPathComponent)\n", stderr)
            exit(1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("FAIL: could not encode \(url.lastPathComponent)\n", stderr)
            exit(1)
        }
        do {
            try data.write(to: url)
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
        window.close()
    }
}
