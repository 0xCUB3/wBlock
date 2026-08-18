import Foundation

@main
struct ApplyProgressPresentationTests {
    @MainActor
    static func main() {
        testFreshRunFocusesUpdating()
        testUpdatingFractionAndProgress()
        testPhaseAdvanceIsMonotonic()
        testSkipPreApplyLandsOnReading()
        testReadingDetailUsesExtensionCount()
        testConvertingShowsCurrentTargetAndFraction()
        testReloadingFractionAndEmptyName()
        testSavingUsesSegmentFloor()
        testCompletedRunIsFull()
        testFailedPhaseWinsFocus()
        testScriptDetails()
        testClampsAndZeroTotals()
        testAccessibilityValue()
        testNodeOrderMatchesPhases()
        testCompletedNodesKeepDetails()
        testBarTracksVisibleStatus()
        testUpdatingShowsCurrentFilter()
        print("PASS")
    }

    @MainActor
    private static func testFreshRunFocusesUpdating() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)

        check(presentation.nodes.count == ApplyChangesPhase.allCases.count, "rail must include every apply phase")
        check(presentation.nodes.first?.phase == .updating, "first rail node must be updating")
        check(presentation.nodes.first?.status == .active, "fresh run must focus updating")
        check(presentation.nodes.dropFirst().allSatisfy { $0.status == .pending }, "later phases start pending")
        check(presentation.title == ApplyChangesPhase.updating.title, "title must be the active phase")
        check(presentation.detail == viewModel.state.statusMessage, "active updating detail is the stage message")
        check(presentation.fractionLabel == nil, "no percent until phase progress exists")
        check(presentation.progress == 0, "fresh run starts at the first segment")
        check(!presentation.isFailed, "a fresh run is not failed")
    }

    @MainActor
    private static func testUpdatingFractionAndProgress() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseProgress(0.4)
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)

        check(presentation.fractionLabel == ApplyProgressPresentation.percentString(0.4), "updating must show a percent")
        checkAlmostEqual(presentation.progress, 0.4 / 6, "updating progress occupies the first sixth")

        viewModel.updatePhaseProgress(1.5)
        let clamped = ApplyProgressPresentation.make(from: viewModel.state)
        check(clamped.fractionLabel == ApplyProgressPresentation.percentString(1), "phase progress must clamp to 100%")
        checkAlmostEqual(clamped.progress, 1.0 / 6, "full local progress reaches the next segment boundary")
    }

    @MainActor
    private static func testPhaseAdvanceIsMonotonic() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        var last = ApplyProgressPresentation.make(from: viewModel.state).progress
        var samples = [last]

        func record(_ message: String) {
            let value = ApplyProgressPresentation.make(from: viewModel.state).progress
            check(value + 0.000_000_1 >= last, "\(message): progress went backwards from \(last) to \(value)")
            last = value
            samples.append(value)
        }

        viewModel.updatePhaseProgress(0.5)
        record("updating halfway")
        viewModel.updateFilterUpdatesFound(3)
        viewModel.updatePhaseCompletion(updating: true, scripts: false)
        record("scripts became active")
        check(
            ApplyProgressPresentation.make(from: viewModel.state).title == ApplyChangesPhase.scripts.title,
            "completing updates must focus scripts"
        )

        viewModel.updatePhaseProgress(1)
        record("scripts finished locally")
        viewModel.updateScriptsUpdateResult(updated: 2, failed: 0)
        viewModel.updatePhaseCompletion(scripts: true, reading: false)
        record("reading became active")

        viewModel.updateProcessedCount(0, total: 5)
        record("extension count arrived")
        viewModel.updatePhaseCompletion(reading: true, converting: false)
        record("converting became active")

        viewModel.updateProcessedCount(0, total: 5)
        for done in 0...5 {
            viewModel.updateConvertingDone(done)
            viewModel.updateCurrentFilter(done == 0 ? "" : "Blocker \(done)")
            record("converting \(done)/5")
        }
        viewModel.updatePhaseCompletion(converting: true, reloading: false)
        record("reloading became active")

        for done in 0...5 {
            viewModel.updateReloadingDone(done)
            record("reloading \(done)/5")
        }
        viewModel.updatePhaseCompletion(reloading: true, saving: false)
        record("saving became active")
        viewModel.updatePhaseCompletion(saving: true)
        record("saving complete")

        let finished = ApplyProgressPresentation.make(from: viewModel.state)
        check(finished.progress == 1, "a finished run must report full progress")
        check(samples.count > 10, "monotonic walk must sample the whole pipeline")
    }

    @MainActor
    private static func testSkipPreApplyLandsOnReading() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateFilterUpdatesFound(4)
        viewModel.updateScriptsUpdateResult(updated: 1, failed: 0)
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)

        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.title == ApplyChangesPhase.reading.title, "skipping downloads should land on reading")
        check(status(presentation, .updating) == .complete, "updating must already be complete")
        check(status(presentation, .scripts) == .complete, "scripts must already be complete")
        check(status(presentation, .reading) == .active, "reading must be the live phase")
        checkAlmostEqual(presentation.progress, (2 + 0.2) / 6, "reading uses a small segment floor")
    }

    @MainActor
    private static func testReadingDetailUsesExtensionCount() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)
        var presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == nil, "reading has no detail before the target count exists")

        viewModel.updateProcessedCount(0, total: 5)
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(
            presentation.detail == localizedCount("Preparing %d extensions", count: 5),
            "reading should name the extension count"
        )
    }

    @MainActor
    private static func testConvertingShowsCurrentTargetAndFraction() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: true, converting: false)
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updateConvertingDone(2)
        viewModel.updateCurrentFilter("Privacy")

        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.title == ApplyChangesPhase.converting.title, "converting title")
        check(presentation.detail == "Privacy", "converting detail is the current target")
        check(presentation.fractionLabel == "2/5", "converting fraction uses done/total")
        checkAlmostEqual(presentation.progress, (3 + 0.4) / 6, "converting 2/5 sits 40% into its segment")
    }

    @MainActor
    private static func testReloadingFractionAndEmptyName() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(
            updating: true,
            scripts: true,
            reading: true,
            converting: true,
            reloading: false
        )
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updateReloadingDone(0)
        viewModel.updateCurrentFilter("")

        var presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == nil, "reloading without a name should not invent one")
        check(presentation.fractionLabel == "0/5", "reloading still shows 0/total")

        viewModel.updateCurrentFilter("Ads")
        viewModel.updateReloadingDone(5)
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == "Ads", "reloading detail is the current target")
        check(presentation.fractionLabel == "5/5", "reloading 5/5")
        checkAlmostEqual(presentation.progress, 5.0 / 6, "full local reload reaches the next boundary")
    }

    @MainActor
    private static func testSavingUsesSegmentFloor() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(
            updating: true,
            scripts: true,
            reading: true,
            converting: true,
            reloading: true,
            saving: false
        )
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.title == ApplyChangesPhase.saving.title, "saving title")
        check(presentation.detail == nil, "saving has no extra detail")
        check(presentation.fractionLabel == nil, "saving has no count label")
        checkAlmostEqual(presentation.progress, (5 + 0.2) / 6, "saving uses the same quiet floor as reading")
    }

    @MainActor
    private static func testCompletedRunIsFull() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateStatistics(
            sourceRules: 10,
            safariRules: 8,
            conversionTime: "0.20s",
            reloadTime: "0.10s"
        )
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.progress == 1, "summary completion is full progress")
        check(presentation.nodes.allSatisfy { $0.status == .complete }, "summary completion marks every phase")
        check(!presentation.isFailed, "a successful summary is not failed")
    }

    @MainActor
    private static func testFailedPhaseWinsFocus() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: true, converting: false)
        viewModel.updateCurrentFilter("Security")
        viewModel.markFailed(message: "Conversion exploded")

        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.isFailed, "failed runs must flag the field")
        check(presentation.title == ApplyChangesPhase.converting.title, "failure keeps the live phase")
        check(presentation.detail == "Conversion exploded", "failure detail is the message")
        check(node(presentation, .converting)?.detail == nil, "failed rows must not repeat the failure card")
        check(status(presentation, .converting) == .failed, "the live phase becomes failed")
        check(status(presentation, .reloading) == .pending, "later phases stay pending")
    }

    @MainActor
    private static func testScriptDetails() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: false)
        viewModel.updateStageDescription("Updating userscripts...")
        var presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == "Updating userscripts...", "script-related status is shown")

        viewModel.updateStageDescription("Applying filters...")
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == nil, "non-script status is hidden on the scripts phase")

        viewModel.updateScriptsUpdateResult(updated: 2, failed: 1)
        // Focus the completed scripts phase by failing to activate a later one after marking complete,
        // then inspect complete-state copy through a local step snapshot.
        viewModel.updatePhaseCompletion(scripts: true, reading: false)
        var state = viewModel.state
        if let index = state.phases.firstIndex(where: { $0.phase == .scripts }) {
            state.phases[index].status = .complete
            state.phases[index + 1].status = .pending
        }
        presentation = ApplyProgressPresentation.make(from: state)
        check(
            presentation.detail == String.localizedStringWithFormat(
                NSLocalizedString("Updated %d, %d failed", comment: "Apply changes script phase detail"),
                2,
                1
            ),
            "completed scripts should report mixed results when focused"
        )

        viewModel.updateScriptsUpdateResult(updated: 3, failed: 0)
        state = viewModel.state
        if let index = state.phases.firstIndex(where: { $0.phase == .scripts }) {
            state.phases[index].status = .complete
            state.phases[index + 1].status = .pending
        }
        presentation = ApplyProgressPresentation.make(from: state)
        check(
            presentation.detail == localizedCount("Updated %d scripts", count: 3),
            "completed scripts should report a success count"
        )

        viewModel.updateScriptsUpdateResult(updated: 0, failed: 0)
        state = viewModel.state
        if let index = state.phases.firstIndex(where: { $0.phase == .scripts }) {
            state.phases[index].status = .complete
            state.phases[index + 1].status = .pending
        }
        presentation = ApplyProgressPresentation.make(from: state)
        check(presentation.detail == String(localized: "No script updates"), "zero script updates have explicit copy")
    }

    @MainActor
    private static func testClampsAndZeroTotals() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: true, converting: false)
        viewModel.updateProcessedCount(0, total: 0)
        viewModel.updateConvertingDone(4)
        var presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.fractionLabel == nil, "converting without a total cannot show a fraction")
        check(!presentation.progress.isNaN, "zero totals must not produce NaN progress")

        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updateConvertingDone(-3)
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.fractionLabel == "0/5", "negative converting counts clamp to zero")

        viewModel.updatePhaseProgress(-4)
        viewModel.updatePhaseCompletion(updating: false)
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.progress >= 0, "negative phase progress cannot go below zero")
    }

    @MainActor
    private static func testAccessibilityValue() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: true, converting: false)
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updateConvertingDone(1)
        viewModel.updateCurrentFilter("Ads")
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.accessibilityValue.contains("Ads"), "VoiceOver value must include the current target")
        check(presentation.accessibilityValue.contains("1/5"), "VoiceOver value must include the fraction")
    }

    @MainActor
    private static func testUpdatingShowsCurrentFilter() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateCurrentFilter("AdGuard Base Filter")
        viewModel.updatePhaseProgress(0.93)
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(presentation.detail == "AdGuard Base Filter", "the live update row must name the in-flight list")
        check(
            node(presentation, .updating)?.detail
                == "AdGuard Base Filter · " + ApplyProgressPresentation.percentString(0.93),
            "the update row should keep the list name and local fraction together"
        )
        checkAlmostEqual(presentation.progress, 0.93 / 6.0, "overall fill stays in the first segment")
    }

    @MainActor
    private static func testBarTracksVisibleStatus() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateFilterUpdatesFound(3)
        viewModel.updateScriptsUpdateResult(updated: 2, failed: 0)
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updatePhaseCompletion(reading: true, converting: false)
        viewModel.updateConvertingDone(2)
        viewModel.updateCurrentFilter("Privacy")

        var presentation = ApplyProgressPresentation.make(from: viewModel.state)
        let complete = presentation.nodes.filter { $0.status == .complete }.count
        check(complete == 3, "three finished rows should already be checked")
        check(presentation.nodes.first(where: { $0.status == .active })?.phase == .converting, "converting is the live row")
        checkAlmostEqual(
            presentation.progress,
            (Double(complete) + 2.0 / 5.0) / 6.0,
            "bar fill must equal finished rows plus the live fraction"
        )
        check(
            presentation.progressLabel == ApplyProgressPresentation.percentString(presentation.progress),
            "the bar caption must describe the same fill as the track"
        )
        check(presentation.progressLabel != presentation.fractionLabel, "the overall bar must not reuse the live row fraction")

        viewModel.updateConvertingDone(4)
        presentation = ApplyProgressPresentation.make(from: viewModel.state)
        checkAlmostEqual(
            presentation.progress,
            (3.0 + 4.0 / 5.0) / 6.0,
            "the bar must move when the live row's fraction moves"
        )
        check(
            presentation.progressLabel == ApplyProgressPresentation.percentString(presentation.progress),
            "the bar caption must stay locked to the new fill"
        )
    }

    @MainActor
    private static func testCompletedNodesKeepDetails() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        viewModel.updateFilterUpdatesFound(3)
        viewModel.updateScriptsUpdateResult(updated: 2, failed: 0)
        viewModel.updatePhaseCompletion(updating: true, scripts: true, reading: false)
        viewModel.updateProcessedCount(0, total: 5)
        viewModel.updatePhaseCompletion(reading: true, converting: false)
        viewModel.updateConvertingDone(2)
        viewModel.updateCurrentFilter("Privacy")

        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(
            node(presentation, .updating)?.detail == localizedCount("Downloaded %d updates", count: 3),
            "completed update rows must keep their count"
        )
        check(
            node(presentation, .scripts)?.detail == localizedCount("Updated %d scripts", count: 2),
            "completed script rows must keep their count"
        )
        check(
            node(presentation, .reading)?.detail == localizedCount("Preparing %d extensions", count: 5),
            "completed reading rows must keep the extension count"
        )
        check(
            node(presentation, .converting)?.detail == "Privacy · 2/5",
            "the active converting row should show the target and fraction"
        )
        check(node(presentation, .reloading)?.detail == nil, "pending reload has no detail")
        check(node(presentation, .saving)?.detail == nil, "pending save has no detail")
    }

    @MainActor
    private static func testNodeOrderMatchesPhases() {
        let viewModel = ApplyChangesViewModel()
        viewModel.beginProgressRun()
        let presentation = ApplyProgressPresentation.make(from: viewModel.state)
        check(
            presentation.nodes.map(\.phase) == ApplyChangesPhase.allCases,
            "rail order must follow ApplyChangesPhase.allCases"
        )
    }

    private static func node(
        _ presentation: ApplyProgressPresentation,
        _ phase: ApplyChangesPhase
    ) -> ApplyProgressPresentation.Node? {
        presentation.nodes.first(where: { $0.phase == phase })
    }

    private static func status(
        _ presentation: ApplyProgressPresentation,
        _ phase: ApplyChangesPhase
    ) -> ApplyChangesPhaseStatus? {
        node(presentation, phase)?.status
    }

    private static func localizedCount(_ key: String, count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Apply changes detail"),
            count
        )
    }

    private static func checkAlmostEqual(_ actual: Double, _ expected: Double, _ message: String) {
        check(abs(actual - expected) < 0.000_1, "\(message) (actual \(actual), expected \(expected))")
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
