import Foundation

/// A Mermaid C4 model diagram (`C4Context` / `C4Container` / `C4Component` /
/// `C4Dynamic` / `C4Deployment`). Elements are people and software boxes;
/// relationships are labelled arrows. Boundaries and deployment nodes are
/// kept as `boundaries`, each element recording the innermost one it sits in,
/// so the layout can draw a frame round the group. (Chartz change; upstream
/// flattened them.)
public struct C4Diagram: Hashable, Sendable {
    /// Which C4 element flavour a box is; drives its styling.
    public enum ElementKind: Hashable, Sendable {
        case person
        case system
        case container
        case component
    }

    /// One person/system/container/component box, keyed by `alias`.
    public struct Element: Hashable, Sendable, Identifiable {
        /// Same as `alias`.
        public var id: String { alias }
        public let alias: String
        /// Display name; falls back to `alias`.
        public let label: String
        /// Technology stack (Container/Component), else nil.
        public let technology: String?
        /// Description text; nil when omitted.
        public let descr: String?
        public let kind: ElementKind
        /// `_Ext` variants: external systems drawn with a muted tint.
        public let external: Bool
        /// Alias of the innermost boundary this element is declared inside,
        /// or nil at the top level.
        public let boundary: String?

        /// Memberwise initializer.
        public init(alias: String, label: String, technology: String?,
                    descr: String?, kind: ElementKind, external: Bool,
                    boundary: String? = nil) {
            self.boundary = boundary
            self.alias = alias
            self.label = label
            self.technology = technology
            self.descr = descr
            self.kind = kind
            self.external = external
        }
    }

    /// A labelled arrow between two element aliases in `elements`.
    public struct Relation: Hashable, Sendable {
        public let from: String
        public let to: String
        public let label: String
        /// Technology annotation (4th `Rel` argument); nil when omitted.
        public let technology: String?

        /// Memberwise initializer.
        public init(from: String, to: String, label: String, technology: String?) {
            self.from = from
            self.to = to
            self.label = label
            self.technology = technology
        }
    }

    /// A `System_Boundary` / `Container_Boundary` / `Enterprise_Boundary` /
    /// `Boundary` block, or a deployment `Node`: a named frame round the
    /// elements declared inside it.
    public struct Boundary: Hashable, Sendable, Identifiable {
        /// Same as `alias`.
        public var id: String { alias }
        public let alias: String
        /// Display name; falls back to `alias`.
        public let label: String
        /// What the frame is, for its caption: "System", "Container",
        /// "Enterprise", "Node", or empty for a plain `Boundary`.
        public let kind: String
        /// Alias of the enclosing boundary, or nil at the top level.
        public let parent: String?

        /// Memberwise initializer.
        public init(alias: String, label: String, kind: String, parent: String?) {
            self.alias = alias
            self.label = label
            self.kind = kind
            self.parent = parent
        }
    }

    public var title: String?
    public var elements: [Element]
    public var relations: [Relation]
    /// In declaration order; a parent always comes before its children.
    public var boundaries: [Boundary]

    /// Memberwise initializer.
    public init(title: String?, elements: [Element], relations: [Relation],
                boundaries: [Boundary] = []) {
        self.title = title
        self.elements = elements
        self.relations = relations
        self.boundaries = boundaries
    }
}

extension MermaidParser {

    /// Parses a C4 body: element calls (`Person(alias, "Label", "descr")`,
    /// `Container(alias, "Label", "tech", "descr")`, `_Ext` variants) and
    /// `Rel(from, to, "label"[, "tech"])` lines. Boundary/Node blocks become
    /// `boundaries`; duplicate aliases keep the first. Nil when no element
    /// parses.
    static func parseC4(body: [String]) -> C4Diagram? {
        var title: String?
        var elements: [C4Diagram.Element] = []
        var relations: [C4Diagram.Relation] = []
        var seen = Set<String>()
        var boundaries: [C4Diagram.Boundary] = []
        var seenBoundaries = Set<String>()
        // Open blocks, innermost last. nil marks a brace we are not tracking
        // (a duplicate or unreadable boundary), so its `}` pops the right entry.
        var openBlocks: [String?] = []

        for line in body {
            if line.hasPrefix("title ") {
                title = String(line.dropFirst("title ".count)).trimmingCharacters(in: .whitespaces)
                continue
            }
            if line == "{" { continue }
            if line.hasPrefix("}") {
                if !openBlocks.isEmpty { openBlocks.removeLast() }
                continue
            }

            // A `Name(args…)` call. Everything else (styles, directives, bare
            // braces) is ignored.
            guard let open = line.firstIndex(of: "(") else { continue }
            let name = String(line[..<open]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, let close = line.lastIndex(of: ")"), line.index(after: open) <= close
            else { continue }
            let inside = String(line[line.index(after: open)..<close])
            let args = c4Args(inside)

            if name.hasPrefix("Rel") || name.hasPrefix("BiRel") {
                // RelIndex(index, from, to, label, ...) leads with an index
                // arg; consuming it as `from` minted a relation from a number
                // to the real source.
                var args = args
                if name.hasPrefix("RelIndex") { args = Array(args.dropFirst()) }
                guard args.count >= 3 else { continue }
                relations.append(C4Diagram.Relation(
                    from: args[0], to: args[1], label: args[2],
                    technology: args.count >= 4 && !args[3].isEmpty ? args[3] : nil
                ))
                continue
            }

            // Boundaries / deployment nodes are frames: remember the block so
            // the elements on the following lines know they are inside it.
            if name.contains("Boundary") || name.hasSuffix("Node") {
                // Only a line that opens a block counts; `Node(...)` with no
                // brace would otherwise swallow everything after it.
                guard line.hasSuffix("{") else { continue }
                let alias = args.first ?? ""
                guard !alias.isEmpty, seenBoundaries.insert(alias).inserted else {
                    openBlocks.append(nil)
                    continue
                }
                let kind: String
                if name.hasSuffix("Node") { kind = "Node" }
                else if name.hasPrefix("System") { kind = "System" }
                else if name.hasPrefix("Container") { kind = "Container" }
                else if name.hasPrefix("Enterprise") { kind = "Enterprise" }
                else { kind = "" }
                boundaries.append(C4Diagram.Boundary(
                    alias: alias,
                    label: args.count >= 2 && !args[1].isEmpty ? args[1] : alias,
                    kind: kind,
                    parent: openBlocks.reversed().compactMap { $0 }.first))
                openBlocks.append(alias)
                continue
            }

            guard let (kind, external) = c4Kind(name), args.count >= 1 else { continue }
            let alias = args[0]
            guard !alias.isEmpty, !seen.contains(alias) else { continue }
            let label = args.count >= 2 && !args[1].isEmpty ? args[1] : alias

            let technology: String?
            let descr: String?
            switch kind {
            case .container, .component:
                technology = args.count >= 3 && !args[2].isEmpty ? args[2] : nil
                descr = args.count >= 4 && !args[3].isEmpty ? args[3] : nil
            case .person, .system:
                technology = nil
                descr = args.count >= 3 && !args[2].isEmpty ? args[2] : nil
            }

            seen.insert(alias)
            elements.append(C4Diagram.Element(
                alias: alias, label: label, technology: technology,
                descr: descr, kind: kind, external: external,
                boundary: openBlocks.reversed().compactMap { $0 }.first
            ))
        }

        guard !elements.isEmpty else { return nil }
        // A frame with nothing in it (directly or nested) has nothing to go
        // round; keep only boundaries that end up holding an element.
        var used = Set<String>()
        let parentOf = Dictionary(boundaries.map { ($0.alias, $0.parent) }, uniquingKeysWith: { a, _ in a })
        for element in elements {
            var current = element.boundary
            while let alias = current, used.insert(alias).inserted { current = parentOf[alias] ?? nil }
        }
        return C4Diagram(title: title, elements: elements, relations: relations,
                         boundaries: boundaries.filter { used.contains($0.alias) })
    }

    /// Maps a C4 element function name to its kind + external flag.
    /// `Person`, `Person_Ext`, `System`, `System_Ext`, `SystemDb`,
    /// `Container`, `ContainerDb_Ext`, `Component`, … Boundaries are excluded
    /// by the caller before this runs (else `System_Boundary` would match).
    private static func c4Kind(_ name: String) -> (C4Diagram.ElementKind, Bool)? {
        let external = name.contains("_Ext")
        let base = name.hasSuffix("_Ext") ? String(name.dropLast(4)) : name
        if base.hasPrefix("Person") { return (.person, external) }
        if base.hasPrefix("Container") { return (.container, external) }
        if base.hasPrefix("Component") { return (.component, external) }
        if base.hasPrefix("System") { return (.system, external) }
        return nil
    }

    /// Splits a C4 argument list on top-level commas, honouring double quotes
    /// and stripping them. Unquoted tokens (the alias) keep their text.
    private static func c4Args(_ inside: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuote = false
        for ch in inside {
            if ch == "\"" { inQuote.toggle(); continue }
            if ch == "," && !inQuote {
                args.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { args.append(last) }
        return args
    }
}
