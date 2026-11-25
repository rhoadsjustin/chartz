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

    /// Works out the language from the text itself: a Structurizr file starts
    /// with `workspace`, once comments and blank lines are skipped. Anything
    /// else is `fallback`.
    ///
    /// Both languages are plain text, so the extension is only a hint: a new
    /// untitled document has none, and people keep DSL in `.txt` files.
    public static func detecting(_ source: String, fallback: DiagramFormat) -> DiagramFormat {
        for raw in source.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("#") || line.hasPrefix("%%") {
                continue
            }
            let first = line.prefix { $0.isLetter }
            if first.lowercased() == "workspace" { return .structurizr }
            // Any other first statement settles it: this is not Structurizr.
            return fallback == .structurizr ? .mermaid : fallback
        }
        return fallback
    }
}
