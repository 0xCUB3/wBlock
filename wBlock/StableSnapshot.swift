import Foundation

/// Rebuilds a value until the state it was read from stays unchanged across the build's awaits,
/// so an edit made while the build was suspended can never be missing from the result.
@MainActor
enum StableSnapshot {
    static func build<State: Equatable, Value>(
        state: () -> State, value: () async -> Value
    ) async -> (value: Value, state: State) {
        while true {
            let before = state()
            let built = await value()
            if state() == before { return (built, before) }
        }
    }
}
