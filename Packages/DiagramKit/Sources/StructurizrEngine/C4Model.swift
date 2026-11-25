import Foundation

/// The C4 model a Structurizr workspace describes: who and what exists, how
/// they relate, and which views to draw of them.
struct C4Workspace: Equatable {
    var name: String?
    var elements: [C4Element] = []
    var relationships: [C4Relationship] = []
    var views: [C4View] = []

    func element(_ id: String) -> C4Element? {
        elements.first { $0.id == id }
    }

    /// The person or software system `id` belongs to: itself for those two,
    /// the owning system for a container or component.
    func topLevel(of id: String) -> C4Element? {
        var current = element(id)
        while let parent = current?.parent, let next = element(parent) {
            current = next
        }
        return current
    }

    /// The container `id` is or sits inside, if any.
    func container(of id: String) -> C4Element? {
        var current = element(id)
        while let found = current {
            if found.kind == .container { return found }
            current = found.parent.flatMap(element)
        }
        return nil
    }
}

struct C4Element: Equatable {
    enum Kind: String, Equatable {
        case person, softwareSystem, container, component
    }

    var id: String
    var kind: Kind
    var name: String
    var description: String?
    var technology: String?
    var tags: Set<String> = []
    /// The enclosing software system (for a container) or container (for a
    /// component). Nil for people and software systems.
    var parent: String?
    /// 1-based source line, for diagnostics.
    var line: Int

    var isExternal: Bool { tags.contains { $0.caseInsensitiveCompare("External") == .orderedSame } }

    var isDatabase: Bool {
        tags.contains { $0.caseInsensitiveCompare("Database") == .orderedSame }
            || (technology?.range(of: "database", options: .caseInsensitive) != nil)
    }
}

struct C4Relationship: Equatable {
    var source: String
    var destination: String
    var description: String?
    var technology: String?
    var line: Int
}

struct C4View: Equatable {
    enum Kind: String, Equatable {
        case systemLandscape, systemContext, container
    }

    var kind: Kind
    /// The software system the view is about. Nil for a landscape.
    var scope: String?
    var key: String?
    var title: String?
    /// Element identifiers named by `include`. Nil means `include *`, which
    /// is also the default when a view has no `include` line.
    var includes: [String]?
    var excludes: [String] = []
    var line: Int
}
