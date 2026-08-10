import Foundation

@main
struct ApplyUpdateCountTests {
    @MainActor
    static func main() {
        let viewModel = ApplyChangesViewModel()

        guard viewModel.state.totalUpdatesFound == 0 else {
            fail("new progress state should start with zero updates")
        }

        viewModel.updateFilterUpdatesFound(7)
        viewModel.updateScriptsUpdateResult(updated: 3, failed: 2)

        guard viewModel.state.filterUpdatesFound == 7 else {
            fail("filter update count was not retained")
        }
        guard viewModel.state.scriptsUpdatedCount == 3 else {
            fail("userscript update count was not retained")
        }
        guard viewModel.state.totalUpdatesFound == 10 else {
            fail("total update count should combine filters and userscripts")
        }
        guard viewModel.state.scriptsFailedCount == 2 else {
            fail("failed userscripts should remain separate from the update total")
        }

        viewModel.updateFilterUpdatesFound(-1)
        viewModel.updateScriptsUpdateResult(updated: -1, failed: -1)
        guard viewModel.state.totalUpdatesFound == 0 else {
            fail("negative update counts should clamp to zero")
        }

        print("PASS")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
