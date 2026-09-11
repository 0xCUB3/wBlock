import Foundation

@main
struct UserScriptUpdateOperationRegression {
    @MainActor
    static func main() async {
        let resolvedURL = URL(string: "https://example.test/resolved.user.js")!
        var fetchCount = 0
        var fetchedURL: URL?

        let succeeded = await UserScriptUpdateOperation.run(
            downloadURL: resolvedURL,
            fetch: { url in
                fetchCount += 1
                fetchedURL = url
                return "payload"
            },
            isCurrent: { true },
            prepare: { $0.uppercased() },
            commit: { prepared in prepared == "PAYLOAD" }
        )
        precondition(succeeded)
        precondition(fetchCount == 1)
        precondition(fetchedURL == resolvedURL)

        let failedCommit = await UserScriptUpdateOperation.run(
            downloadURL: resolvedURL,
            fetch: { _ in "payload" },
            isCurrent: { true },
            prepare: { $0 },
            commit: { _ in false }
        )
        precondition(!failedCommit)

        var current = true
        var committed = false
        let superseded = await UserScriptUpdateOperation.run(
            downloadURL: resolvedURL,
            fetch: { _ in
                current = false
                return "payload"
            },
            isCurrent: { current },
            prepare: { $0 },
            commit: { _ in
                committed = true
                return true
            }
        )
        precondition(!superseded)
        precondition(!committed)

        var cancelledCommit = false
        let cancelled = await Task { @MainActor in
            await UserScriptUpdateOperation.run(
                downloadURL: resolvedURL,
                fetch: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "payload"
                },
                isCurrent: { true },
                prepare: { $0 },
                commit: { _ in
                    cancelledCommit = true
                    return true
                }
            )
        }.value
        precondition(!cancelled)
        precondition(!cancelledCommit)

        var supersededDuringPreparation = false
        var committedAfterPreparationSupersession = false
        let preparationSuperseded = await UserScriptUpdateOperation.run(
            downloadURL: resolvedURL,
            fetch: { _ in "payload" },
            isCurrent: { !supersededDuringPreparation },
            prepare: { payload in
                supersededDuringPreparation = true
                return payload
            },
            commit: { _ in
                committedAfterPreparationSupersession = true
                return true
            }
        )
        precondition(!preparationSuperseded)
        precondition(!committedAfterPreparationSupersession)

        print("userscript update operation regression: PASS")
    }
}
