import Foundation

/// A coloured run of diagram source.
public struct SourceToken: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case comment, string, keyword, arrow
    }

    /// UTF-16 range, the unit TextKit works in.
    public let range: NSRange
    public let kind: Kind

    public init(range: NSRange, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// Finds the runs of source worth colouring.
///
/// This is a scanner, not a parser: it knows what comments, strings, keywords
/// and arrows look like, and nothing about whether the diagram is valid. That
/// keeps it fast enough to rerun on every keystroke and means half-typed
/// source still gets coloured.
public enum SourceHighlighter {
    /// Tokens in `source`, in order of position, never overlapping.
    public static func tokens(in source: String, format: DiagramFormat) -> [SourceToken] {
        let rules = format == .mermaid ? mermaidRules : structurizrRules
        let text = source as NSString
        let whole = NSRange(location: 0, length: text.length)
        var taken = IndexSet()
        var tokens: [SourceToken] = []
        // Rules run in priority order: an arrow inside a comment or a string
        // is part of that comment or string.
        for rule in rules {
            rule.regex.enumerateMatches(in: source, range: whole) { match, _, _ in
                guard let range = match?.range, range.length > 0 else { return }
                let indexes = range.location..<(range.location + range.length)
                guard !taken.intersects(integersIn: indexes) else { return }
                taken.insert(integersIn: indexes)
                tokens.append(SourceToken(range: range, kind: rule.kind))
            }
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Rules

    private struct Rule: @unchecked Sendable {
        let kind: SourceToken.Kind
        let regex: NSRegularExpression

        init(_ kind: SourceToken.Kind, _ pattern: String) {
            self.kind = kind
            // The patterns are literals in this file; a bad one is a
            // programmer error that the unit tests catch.
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
    }

    private static func words(_ list: [String]) -> String {
        // Longest first, so `stateDiagram-v2` wins over `stateDiagram`.
        let alternatives = list.sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return "(?<![A-Za-z0-9_])(?:\(alternatives))(?![A-Za-z0-9_])"
    }

    private static let mermaidRules: [Rule] = [
        Rule(.comment, "%%.*$"),
        Rule(.string, "\"[^\"\\n]*\""),
        Rule(.keyword, words([
            // Diagram types.
            "flowchart", "graph", "sequenceDiagram", "classDiagram", "stateDiagram",
            "stateDiagram-v2", "erDiagram", "gantt", "pie", "journey", "gitGraph",
            "mindmap", "timeline", "quadrantChart", "requirementDiagram",
            "C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment",
            // Structure.
            "subgraph", "end", "direction", "title", "section", "participant", "actor",
            "as", "note", "over", "loop", "alt", "else", "opt", "par", "and", "rect",
            "activate", "deactivate", "class", "state", "classDef", "style", "linkStyle",
            "click", "TD", "TB", "BT", "LR", "RL",
            // C4.
            "Person", "Person_Ext", "System", "System_Ext", "SystemDb", "SystemDb_Ext",
            "Container", "Container_Ext", "ContainerDb", "ContainerDb_Ext",
            "Component", "Component_Ext", "Rel", "Rel_Back", "BiRel", "Boundary",
            "Enterprise_Boundary", "System_Boundary", "Container_Boundary",
            "UpdateLayoutConfig",
        ])),
        Rule(.arrow, "[<ox]?(?:--+|==+|-\\.+-|\\.\\.+|~~+)[>ox)]*|->>?|-[x)]"),
    ]

    private static let structurizrRules: [Rule] = [
        Rule(.comment, "(?://|#).*$"),
        Rule(.string, "\"[^\"\\n]*\""),
        Rule(.keyword, words([
            "workspace", "model", "views", "person", "softwareSystem", "container",
            "component", "group", "enterprise", "deploymentEnvironment", "deploymentNode",
            "containerInstance", "softwareSystemInstance", "systemLandscape",
            "systemContext", "dynamic", "deployment", "include", "exclude", "autoLayout",
            "autolayout", "styles", "element", "relationship", "theme", "themes", "tags",
            "description", "technology", "title",
        ])),
        Rule(.arrow, "->"),
    ]
}

/// Small, UI-free editing rules shared by the iOS and Mac editors.
public enum SourceEditing {
    /// What the tab key inserts.
    public static let indentUnit = "    "

    /// What Return inserts at `location` (a UTF-16 offset): a newline, plus
    /// the leading whitespace of the line the caret is on, so nested blocks
    /// keep their indent.
    public static func newline(in text: String, at location: Int) -> String {
        let ns = text as NSString
        let caret = min(max(location, 0), ns.length)
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        var end = lineStart
        while end < caret {
            let character = ns.character(at: end)
            guard character == 0x20 || character == 0x09 else { break }
            end += 1
        }
        return "\n" + ns.substring(with: NSRange(location: lineStart, length: end - lineStart))
    }
}
