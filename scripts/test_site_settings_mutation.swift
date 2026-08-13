#!/usr/bin/env swift

import Foundation

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let source = try String(contentsOfFile: "wBlock/SiteSettingsView.swift", encoding: .utf8)
check(source.contains("@State private var isMutationInFlight = false"), "Site mutations must expose a busy state")
check(source.contains("@State private var mutationGeneration = 0"), "Site mutations must carry a generation")
check(source.contains("guard !isMutationInFlight else { return nil }"), "Rapid toggles must not start overlapping mutations")
check(source.contains("guard generation == mutationGeneration else { return }"), "Stale completions must not update undo/redo snapshots")
check(source.contains(".disabled(isMutationInFlight)"), "Site controls must be disabled during mutation")
check(source.contains("defer { finishMutation(generation) }"), "Mutation completion must always release the busy state")

actor MutationGate {
    private var inFlight = false
    private var generation = 0

    func begin() -> Int? {
        guard !inFlight else { return nil }
        generation += 1
        inFlight = true
        return generation
    }

    func finish(_ candidate: Int) {
        guard candidate == generation else { return }
        inFlight = false
    }

    func currentGeneration() -> Int { generation }
}

let gate = MutationGate()
let first = await gate.begin()
check(first == 1, "first user mutation should start")
let overlapping = await gate.begin()
check(overlapping == nil, "rapid second toggle must be ignored while the first is pending")
await gate.finish(first!)
let second = await gate.begin()
check(second == 2, "next mutation should start only after the first completes")
check(await gate.currentGeneration() == 2, "the latest completed mutation owns the new generation")
await gate.finish(second!)

print("PASS: site settings mutation serialization and stale-state guard")
