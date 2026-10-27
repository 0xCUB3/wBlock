import Foundation

// State transitions are proven and compared with the ViewModel in scripts/proofs.
// Keep actual formatting, floating-point progress, and setter behavior here.
@main struct ApplyProgressPresentationTests {
  @MainActor static func main() {
    let phases = ApplyChangesPhase.allCases
    func count(_ key: String, _ n: Int) -> String {
      String.localizedStringWithFormat(NSLocalizedString(key, comment: "Apply changes detail"), n)
    }
    let vm = ApplyChangesViewModel()
    vm.beginProgressRun()
    let fresh = ApplyProgressPresentation.make(from: vm.state)
    precondition(
      fresh.progress == 0 && fresh.detail == vm.state.statusMessage && fresh.fractionLabel == nil && !fresh.isFailed)
    precondition(fresh.nodes.first?.status == .active && fresh.nodes.dropFirst().allSatisfy { $0.status == .pending })
    for (i, phase) in phases.enumerated() {
      for status: ApplyChangesPhaseStatus in [.active, .complete, .failed] {
        for total in [-1, 0, 1, 5] {
          for done in [-3, 0, 2, 7] {
            for fraction in [-4.0, 0, 0.4, 1.5] {
              vm.beginProgressRun()
              vm.updateProcessedCount(0, total: total)
              vm.updateConvertingDone(done)
              vm.updateReloadingDone(done)
              vm.updatePhaseProgress(fraction)
              var s = vm.state
              s.statusMessage = "status"
              s.failureMessage = "failure"
              s.currentFilterName = "target"
              s.phases = phases.enumerated().map { j, p in
                .init(phase: p, status: j < i ? .complete : j == i ? status : .pending)
              }
              let p = ApplyProgressPresentation.make(from: s)
              let node = p.nodes[i]
              let clamped = min(1, max(0, fraction))
              let local =
                phase == .updating
                ? clamped
                : (phase == .reading || phase == .saving)
                  ? 0.2 : total > 0 ? min(1, Double(max(0, done)) / Double(total)) : 0
              let expected = status == .complete ? Double(i + 1) / 5 : (Double(i) + local) / 5
              precondition(abs(p.progress - expected) < 1e-9 && p.progress.isFinite)
              precondition(p.title == phase.title && p.nodes.map(\.phase) == phases)
              precondition(
                p.progressLabel == ApplyProgressPresentation.percentString(expected)
                  && p.accessibilityValue == p.progressLabel)
              precondition(p.isFailed == (status == .failed))
              let label =
                status != .active
                ? nil
                : phase == .updating
                  ? (clamped > 0 ? ApplyProgressPresentation.percentString(clamped) : nil)
                  : (phase == .converting || phase == .reloading) && total > 0 ? "\(max(0, done))/\(total)" : nil
              precondition(p.fractionLabel == label && node.accessory == label)
              let detail: String? =
                status == .failed
                ? "failure"
                : phase == .updating
                  ? (status == .active ? "target" : String(localized: "No updates available"))
                  : phase == .reading
                    ? (total > 0 ? count("Preparing %d extensions", total) : nil)
                    : (phase == .converting || phase == .reloading) && status == .active ? "target" : nil
              precondition(p.detail == detail && node.detail == (status == .failed ? nil : detail))
              let spoken =
                status == .failed
                ? String(localized: "Failed") : [node.detail, label].compactMap { $0 }.joined(separator: " · ")
              precondition(node.accessibilityValue == spoken)
              if status == .active && (phase == .converting || phase == .reloading) {
                s.currentFilterName = ""
                precondition(ApplyProgressPresentation.make(from: s).detail == nil)
              }
            }
          }
        }
      }
    }
    for filters in 0...2 {
      for scripts in 0...2 {
        for failed in 0...2 {
          vm.beginProgressRun()
          vm.updateFilterUpdatesFound(filters)
          vm.updateScriptsUpdateResult(updated: scripts, failed: failed)
          vm.updatePhaseCompletion(scripts: true, reading: false)
          let p = ApplyProgressPresentation.make(from: vm.state)
          let parts = [
            ("Updated %d filters", filters), ("Updated %d scripts", scripts), ("%d script update(s) failed", failed),
          ].filter { $0.1 > 0 }.map { count($0.0, $0.1) }
          precondition(
            p.nodes[0].detail
              == (parts.isEmpty ? String(localized: "No updates available") : parts.joined(separator: " · ")))
        }
      }
    }
    vm.beginProgressRun()
    vm.updateFiltersChecked(12, total: 87)
    precondition(ApplyProgressPresentation.make(from: vm.state).fractionLabel == "12/87")
    precondition(abs(ApplyProgressPresentation.make(from: vm.state).progress - 12.0 / 87 / 5) < 1e-9)
    vm.updateFiltersChecked(90, total: 87)
    precondition(vm.state.filtersCheckedDone == 87)
    vm.updateFiltersChecked(10, total: 10)
    vm.updatePhaseCompletion(updating: true, scripts: false)
    vm.updateScriptsChecked(3, total: 12)
    vm.updateCurrentScript("script")
    precondition(ApplyProgressPresentation.make(from: vm.state).fractionLabel == "13/22")
    precondition(ApplyProgressPresentation.make(from: vm.state).detail == "script")
    vm.updateScriptsChecked(20, total: 12)
    precondition(ApplyProgressPresentation.make(from: vm.state).fractionLabel == "22/22")
    vm.updateCurrentScript("")
    vm.updateStageDescription("status")
    precondition(ApplyProgressPresentation.make(from: vm.state).detail == "status")
    vm.updateFiltersChecked(-1, total: -2)
    vm.updateScriptsChecked(-1, total: -2)
    vm.updatePhaseProgress(0.25)
    precondition(vm.state.filtersCheckedDone == 0 && vm.state.scriptsCheckedDone == 0)
    precondition(
      ApplyProgressPresentation.make(from: vm.state).fractionLabel == ApplyProgressPresentation.percentString(0.25))
    var previous = 0.0
    for phase in phases {
      switch phase {
      case .updating:
        vm.updatePhaseProgress(1)
        vm.updatePhaseCompletion(scripts: true)
      case .reading: vm.updatePhaseCompletion(reading: true)
      case .converting: vm.updatePhaseCompletion(converting: true)
      case .reloading: vm.updatePhaseCompletion(reloading: true)
      case .saving: vm.updatePhaseCompletion(saving: true)
      }
      let progress = ApplyProgressPresentation.make(from: vm.state).progress
      precondition(progress >= previous)
      previous = progress
    }
    precondition(previous == 1)
    vm.beginProgressRun()
    vm.updateCurrentFilter("")
    var unnamed = vm.state
    unnamed.statusMessage = ""
    precondition(ApplyProgressPresentation.make(from: unnamed).detail == nil)
    vm.updateStatistics(sourceRules: 10, safariRules: 8, conversionTime: "0.2s", reloadTime: "0.1s")
    precondition(
      ApplyProgressPresentation.make(from: vm.state).progress == 1
        && vm.state.phases.allSatisfy { $0.status == .complete })
    print("PASS: progress formatting, numeric boundaries, accessibility, and setters")
  }
}
