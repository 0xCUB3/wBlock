import Foundation

public struct AsyncDelay: Sendable, Equatable, CustomStringConvertible {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static func seconds(_ seconds: Int) -> AsyncDelay {
        AsyncDelay(nanoseconds: clampedNanoseconds(seconds, multiplier: 1_000_000_000))
    }

    public static func seconds(_ seconds: TimeInterval) -> AsyncDelay {
        guard seconds > 0 else { return AsyncDelay(nanoseconds: 0) }
        let nanoseconds = seconds * 1_000_000_000
        return AsyncDelay(nanoseconds: nanoseconds >= Double(UInt64.max) ? UInt64.max : UInt64(nanoseconds))
    }

    public static func milliseconds(_ milliseconds: Int) -> AsyncDelay {
        AsyncDelay(nanoseconds: clampedNanoseconds(milliseconds, multiplier: 1_000_000))
    }

    public var description: String {
        if nanoseconds.isMultiple(of: 1_000_000_000) {
            return "\(nanoseconds / 1_000_000_000)s"
        }
        if nanoseconds.isMultiple(of: 1_000_000) {
            return "\(nanoseconds / 1_000_000)ms"
        }
        return "\(nanoseconds)ns"
    }

    private static func clampedNanoseconds(_ value: Int, multiplier: UInt64) -> UInt64 {
        guard value > 0 else { return 0 }
        let unsignedValue = UInt64(value)
        guard unsignedValue <= UInt64.max / multiplier else { return UInt64.max }
        return unsignedValue * multiplier
    }
}

public enum TaskSleep {
    public static func sleep(for delay: AsyncDelay) async throws {
        try await Task.sleep(nanoseconds: delay.nanoseconds)
    }
}
