import Foundation

/// The source languages the app understands.
public enum DiagramFormat: String, CaseIterable, Codable, Hashable, Sendable {
    /// Mermaid, including its `C4Context` / `C4Container` family.
    case mermaid
    /// Structurizr DSL (C4 model as code). Engine lands in milestone 3.
    case structurizr

    public var displayName: String {
        switch self {
        case .mermaid: return "Mermaid"
        case .structurizr: return "Structurizr DSL"
        }
    }

    /// Preferred file extension, without the dot.
    public var fileExtension: String {
        switch self {
        case .mermaid: return "mmd"
        case .structurizr: return "dsl"
        }
    }

    /// Best guess from a file extension. Unknown extensions fall back to Mermaid.
    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "dsl", "structurizr": self = .structurizr
        default: self = .mermaid
        }
    }
}
