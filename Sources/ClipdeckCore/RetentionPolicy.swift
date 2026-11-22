import Foundation

public struct RetentionPolicy: Equatable, Sendable {
    public let maxAge: TimeInterval?
    public let maxItems: Int?

    public init(maxAge: TimeInterval?, maxItems: Int?) {
        self.maxAge = maxAge
        self.maxItems = maxItems
    }

    public func cutoff(now: Date) -> Date? {
        maxAge.map { now.addingTimeInterval(-$0) }
    }
}

public enum RetentionOption: Int, CaseIterable, Identifiable, Sendable {
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case threeMonths = 90
    case oneYear = 365
    case forever = 0

    public static let maxItems = 10_000

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .oneDay: "1 day"
        case .oneWeek: "1 week"
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .oneYear: "1 year"
        case .forever: "Forever"
        }
    }

    public var policy: RetentionPolicy {
        RetentionPolicy(maxAge: self == .forever ? nil : TimeInterval(rawValue) * 86_400, maxItems: Self.maxItems)
    }
}
