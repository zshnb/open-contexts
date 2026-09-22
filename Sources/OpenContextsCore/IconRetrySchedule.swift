public struct IconRetrySchedule: Equatable {
    private static let delays: [Double] = [1, 3, 10]
    private var index = 0

    public init() {}

    public var isExhausted: Bool { index == Self.delays.count }

    public mutating func nextDelay() -> Double? {
        guard index < Self.delays.count else { return nil }
        defer { index += 1 }
        return Self.delays[index]
    }

    public mutating func stop() {
        index = Self.delays.count
    }
}
