import Foundation

/// One problem (or note) an engine found in a diagram's source.
public struct Diagnostic: Identifiable, Hashable, Sendable {
    public enum Severity: String, Hashable, Sendable {
        /// The source cannot produce a diagram.
        case error
        /// The source renders, but part of it was set aside.
        case note
    }

    public let id = UUID()
    public let severity: Severity
    /// 1-based line in the source, or nil when the problem is about the whole file.
    public let line: Int?
    public let message: String

    public init(severity: Severity, line: Int?, message: String) {
        self.severity = severity
        self.line = line
        self.message = message
    }

    /// "Line 3: unknown diagram type" or just the message for whole-file problems.
    public var summary: String {
        if let line { return "Line \(line): \(message)" }
        return message
    }

    // Identity is for SwiftUI lists; equality is about content.
    public static func == (lhs: Diagnostic, rhs: Diagnostic) -> Bool {
        lhs.severity == rhs.severity && lhs.line == rhs.line && lhs.message == rhs.message
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(severity)
        hasher.combine(line)
        hasher.combine(message)
    }
}

public extension Sequence where Element == Diagnostic {
    var containsError: Bool { contains { $0.severity == .error } }
}
