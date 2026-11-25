import Foundation

/// Turns one view of a C4 model into Mermaid C4 source, which the Mermaid
/// engine already knows how to lay out and draw. Both languages therefore
/// share one renderer, and anything that improves C4 drawing improves both.
enum C4Lowering {
    /// The Mermaid source for `view`, or nil when the view has nothing in it.
    static func mermaid(for view: C4View, in workspace: C4Workspace) -> String? {
        let scene = scene(for: view, in: workspace)
        guard !scene.outside.isEmpty || !scene.inside.isEmpty else { return nil }

        var lines = [view.kind == .container ? "C4Container" : "C4Context"]
        lines.append("    title \(clean(title(of: view, in: workspace)))")
        for element in scene.outside {
            lines.append("    " + declaration(element, focus: view.scope, in: view))
        }
        if let scope = view.scope.flatMap(workspace.element), !scene.inside.isEmpty {
            lines.append("    System_Boundary(\(alias(scope.id))_boundary, \(quoted(scope.name))) {")
            for element in scene.inside {
                lines.append("        " + declaration(element, focus: view.scope, in: view))
            }
            lines.append("    }")
        }
        for relation in scene.relations {
            var call = "    Rel(\(alias(relation.source)), \(alias(relation.destination)), \(quoted(relation.description ?? ""))"
            if let technology = relation.technology { call += ", \(quoted(technology))" }
            lines.append(call + ")")
        }
        return lines.joined(separator: "\n")
    }

    /// What the picker calls the view.
    static func title(of view: C4View, in workspace: C4Workspace) -> String {
        if let title = view.title, !title.isEmpty { return title }
        let subject = view.scope.flatMap(workspace.element)?.name
        switch view.kind {
        case .systemLandscape: return workspace.name.map { "System Landscape: \($0)" } ?? "System Landscape"
        case .systemContext: return "System Context: \(subject ?? "")"
        case .container: return "Containers: \(subject ?? "")"
        }
    }

    // MARK: - Choosing what is in the picture

    struct Scene: Equatable {
        /// Elements drawn at the top level, in model order.
        var outside: [C4Element] = []
        /// Elements drawn inside the scoped system's boundary.
        var inside: [C4Element] = []
        var relations: [C4Relationship] = []
    }

    static func scene(for view: C4View, in workspace: C4Workspace) -> Scene {
        // Every relationship is drawn between the things this kind of view
        // shows. A context view shows people and systems, so "web app ->
        // database" inside one system vanishes, while "web app -> other
        // system" becomes "this system -> other system".
        func represent(_ id: String) -> String? {
            guard let top = workspace.topLevel(of: id) else { return nil }
            if view.kind == .container, top.id == view.scope {
                // Inside the system in focus: show the container. The system
                // itself has no box in its own container view.
                return workspace.container(of: id)?.id
            }
            return top.id
        }

        var relations: [C4Relationship] = []
        var seen = Set<String>()
        for relationship in workspace.relationships {
            guard let source = represent(relationship.source),
                  let destination = represent(relationship.destination),
                  source != destination
            else { continue }
            let key = "\(source)\u{1F}\(destination)\u{1F}\(relationship.description ?? "")"
            guard seen.insert(key).inserted else { continue }
            var lifted = relationship
            lifted.source = source
            lifted.destination = destination
            relations.append(lifted)
        }

        // Which elements `include *` means for this kind of view.
        var chosen = Set<String>()
        switch view.kind {
        case .systemLandscape:
            for element in workspace.elements where element.parent == nil {
                chosen.insert(element.id)
            }
        case .systemContext:
            guard let scope = view.scope else { break }
            chosen.insert(scope)
            for relation in relations where relation.source == scope || relation.destination == scope {
                chosen.insert(relation.source)
                chosen.insert(relation.destination)
            }
        case .container:
            guard let scope = view.scope else { break }
            let containers = Set(workspace.elements.filter { $0.kind == .container && $0.parent == scope }.map(\.id))
            chosen.formUnion(containers)
            for relation in relations
            where containers.contains(relation.source) || containers.contains(relation.destination) {
                chosen.insert(relation.source)
                chosen.insert(relation.destination)
            }
        }

        // An explicit include list replaces the default, apart from the
        // view's own subject, which is always there.
        if let includes = view.includes {
            var explicit = Set(includes.compactMap(represent))
            if view.kind == .systemContext, let scope = view.scope { explicit.insert(scope) }
            chosen = explicit
        }
        chosen.subtract(view.excludes.compactMap(represent))

        var scene = Scene()
        for element in workspace.elements where chosen.contains(element.id) {
            if view.kind == .container, element.parent == view.scope, element.kind == .container {
                scene.inside.append(element)
            } else {
                scene.outside.append(element)
            }
        }
        scene.relations = relations.filter { chosen.contains($0.source) && chosen.contains($0.destination) }
        return scene
    }

    // MARK: - Writing Mermaid

    private static func declaration(_ element: C4Element, focus: String?, in view: C4View) -> String {
        let id = alias(element.id)
        let name = quoted(element.name)
        let description = quoted(element.description ?? "")
        switch element.kind {
        case .person:
            return "\(element.isExternal ? "Person_Ext" : "Person")(\(id), \(name), \(description))"
        case .softwareSystem:
            // The system a view is about stands out; in a landscape nothing
            // is "the" system, so only the External tag marks one down.
            let isOther = focus != nil && element.id != focus
            return "\(element.isExternal || isOther ? "System_Ext" : "System")(\(id), \(name), \(description))"
        case .container, .component:
            let macro = element.kind == .component ? "Component" : (element.isDatabase ? "ContainerDb" : "Container")
            return "\(macro)(\(id), \(name), \(quoted(element.technology ?? "")), \(description))"
        }
    }

    /// Mermaid aliases are bare words; Structurizr identifiers may contain
    /// dots and dashes.
    static func alias(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
    }

    /// Text safe to put between the quotes of a Mermaid C4 argument.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func quoted(_ text: String) -> String {
        "\"\(clean(text))\""
    }
}
