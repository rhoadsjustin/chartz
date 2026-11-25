import DiagramCore
import Foundation

/// Reads the subset of the Structurizr DSL the app can draw.
///
/// Supported: `workspace`, `model` with `person`, `softwareSystem`,
/// `container`, `component`, `group` and relationships; `views` with
/// `systemLandscape`, `systemContext` and `container` views, each with
/// `include`, `exclude` and `title`.
///
/// Everything else is skipped, with a note saying so, rather than rejected:
/// a real-world workspace with styles and deployment views should still draw
/// its context and container diagrams.
struct StructurizrParser {
    struct Output {
        var workspace = C4Workspace()
        var diagnostics: [Diagnostic] = []
    }

    static func parse(_ source: String) -> Output {
        var parser = StructurizrParser()
        parser.run(source)
        return parser.output
    }

    // MARK: - Tokens

    enum Token: Equatable {
        case word(String)
        case string(String)
        case open, close, equals, arrow

        var text: String? {
            switch self {
            case .word(let value), .string(let value): return value
            default: return nil
            }
        }
    }

    /// Splits one line into tokens. `inBlockComment` carries `/* ... */`
    /// state from line to line.
    static func tokenize(_ line: String, inBlockComment: inout Bool) -> [Token] {
        var tokens: [Token] = []
        var word = ""
        let characters = Array(line)
        var index = 0

        func flush() {
            guard !word.isEmpty else { return }
            tokens.append(word == "->" ? .arrow : .word(word))
            word = ""
        }

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if inBlockComment {
                if character == "*", next == "/" {
                    inBlockComment = false
                    index += 1
                }
            } else if character == "/", next == "*" {
                flush()
                inBlockComment = true
                index += 1
            } else if (character == "/" && next == "/") || (character == "#" && word.isEmpty) {
                break
            } else if character == "\"" {
                flush()
                var value = ""
                index += 1
                while index < characters.count, characters[index] != "\"" {
                    if characters[index] == "\\", index + 1 < characters.count {
                        index += 1
                    }
                    value.append(characters[index])
                    index += 1
                }
                tokens.append(.string(value))
            } else if character == "{" {
                flush()
                tokens.append(.open)
            } else if character == "}" {
                flush()
                tokens.append(.close)
            } else if character == "=" {
                flush()
                tokens.append(.equals)
            } else if character.isWhitespace {
                flush()
            } else {
                word.append(character)
            }
            index += 1
        }
        flush()
        return tokens
    }

    // MARK: - State

    private enum Context: Equatable {
        case workspace, model, views
        /// Inside the braces of the element with this identifier.
        case element(String)
        /// A `group` or `enterprise`: its children belong to whatever encloses it.
        case group
        /// Inside the braces of `views[index]`.
        case view(Int)
        /// A block we do not understand; everything up to its `}` is dropped.
        case skipped
    }

    private var output = Output()
    private var stack: [Context] = []
    private var sawWorkspace = false
    private var generatedIDs = 0
    private var notedStyles = false
    /// Relationship endpoints are checked once the whole model is read, so
    /// an element can be used before the line that defines it.
    private var pendingRelationships: [C4Relationship] = []

    private mutating func error(_ message: String, line: Int?) {
        output.diagnostics.append(Diagnostic(severity: .error, line: line, message: message))
    }

    private mutating func note(_ message: String, line: Int?) {
        output.diagnostics.append(Diagnostic(severity: .note, line: line, message: message))
    }

    // MARK: - Driver

    private mutating func run(_ source: String) {
        var inBlockComment = false
        var lastLine = 0
        for (offset, raw) in source.components(separatedBy: "\n").enumerated() {
            let line = offset + 1
            lastLine = line
            // A line is usually one statement, optionally opening a block,
            // but `a = person "A" { tags "x" }` is legal too, so walk the
            // braces rather than assuming where they are.
            var pending: [Token] = []
            for token in Self.tokenize(raw, inBlockComment: &inBlockComment) {
                switch token {
                case .open:
                    statement(pending, opensBlock: true, line: line)
                    pending = []
                case .close:
                    if !pending.isEmpty {
                        statement(pending, opensBlock: false, line: line)
                        pending = []
                    }
                    if stack.isEmpty {
                        error("Unexpected '}'", line: line)
                    } else {
                        stack.removeLast()
                    }
                default:
                    pending.append(token)
                }
            }
            if !pending.isEmpty {
                statement(pending, opensBlock: false, line: line)
            }
        }

        if !sawWorkspace {
            error("Expected the file to start with 'workspace {'", line: nil)
        } else if !stack.isEmpty {
            error("Missing '}': \(stack.count) block\(stack.count == 1 ? " is" : "s are") still open at the end of the file", line: lastLine)
        }
        resolveRelationships()
        checkViews()
    }

    private mutating func statement(_ tokens: [Token], opensBlock: Bool, line: Int) {
        guard !tokens.isEmpty else {
            // A brace on a line of its own: a block with no header to read.
            if opensBlock { stack.append(.skipped) }
            return
        }
        guard let context = stack.last else {
            if tokens.first?.text?.lowercased() == "workspace", opensBlock {
                sawWorkspace = true
                output.workspace.name = tokens.dropFirst().first?.text
                stack.append(.workspace)
            } else {
                if opensBlock { stack.append(.skipped) }
                if !sawWorkspace {
                    error("Expected 'workspace {' before anything else", line: line)
                    sawWorkspace = true  // Report it once, not for every line.
                }
            }
            return
        }

        switch context {
        case .skipped:
            if opensBlock { stack.append(.skipped) }
        case .workspace:
            workspaceStatement(tokens, opensBlock: opensBlock, line: line)
        case .model, .group:
            modelStatement(tokens, opensBlock: opensBlock, line: line, owner: enclosingElement())
        case .element(let id):
            modelStatement(tokens, opensBlock: opensBlock, line: line, owner: id)
        case .views:
            viewsStatement(tokens, opensBlock: opensBlock, line: line)
        case .view(let index):
            viewStatement(tokens, opensBlock: opensBlock, line: line, index: index)
        }
    }

    /// The nearest element whose braces we are inside, looking through groups.
    private func enclosingElement() -> String? {
        for context in stack.reversed() {
            if case .element(let id) = context { return id }
        }
        return nil
    }

    // MARK: - Workspace

    private mutating func workspaceStatement(_ tokens: [Token], opensBlock: Bool, line: Int) {
        let keyword = tokens.first?.text?.lowercased() ?? ""
        switch (keyword, opensBlock) {
        case ("model", true):
            stack.append(.model)
        case ("views", true):
            stack.append(.views)
        case ("name", false):
            output.workspace.name = tokens.dropFirst().first?.text
        case ("description", false), ("!docs", false), ("!adrs", false), ("!impliedrelationships", false):
            break
        case ("!identifiers", false):
            if tokens.dropFirst().first?.text?.lowercased() == "hierarchical" {
                note("Hierarchical identifiers are not supported yet; identifiers are treated as flat", line: line)
            }
        default:
            if opensBlock { stack.append(.skipped) }
            note("'\(keyword)' is not supported yet and was left out", line: line)
        }
    }

    // MARK: - Model

    private static let elementKinds: [String: C4Element.Kind] = [
        "person": .person,
        "softwaresystem": .softwareSystem,
        "container": .container,
        "component": .component,
    ]

    private mutating func modelStatement(
        _ tokens: [Token], opensBlock: Bool, line: Int, owner: String?
    ) {
        // A relationship: `a -> b "Uses" "HTTPS"`, or `-> b` inside an element.
        if let arrow = tokens.firstIndex(of: .arrow), arrow <= 1 {
            relationship(tokens, arrow: arrow, opensBlock: opensBlock, line: line, owner: owner)
            return
        }

        var rest = tokens[...]
        var identifier: String?
        if rest.count >= 2, rest[rest.startIndex + 1] == .equals, case .word(let id) = rest[rest.startIndex] {
            identifier = id
            rest = rest.dropFirst(2)
        }
        guard case .word(let rawKeyword)? = rest.first else {
            if opensBlock { stack.append(.skipped) }
            note("Couldn't read this line; left out of the model", line: line)
            return
        }
        let keyword = rawKeyword.lowercased()
        let arguments = rest.dropFirst().compactMap(\.text)

        if let kind = Self.elementKinds[keyword] {
            element(
                kind, identifier: identifier, arguments: arguments,
                opensBlock: opensBlock, line: line, owner: owner)
            return
        }

        switch keyword {
        case "group", "enterprise":
            if opensBlock { stack.append(.group) }
        case "tags" where owner != nil:
            update(owner) { element in
                for argument in arguments {
                    for tag in argument.split(separator: ",") {
                        element.tags.insert(tag.trimmingCharacters(in: .whitespaces))
                    }
                }
            }
        case "description" where owner != nil:
            update(owner) { $0.description = arguments.first }
        case "technology" where owner != nil:
            update(owner) { $0.technology = arguments.first }
        case "url", "properties", "perspectives":
            if opensBlock { stack.append(.skipped) }
        default:
            if opensBlock { stack.append(.skipped) }
            note("'\(rawKeyword)' is not supported yet and was left out", line: line)
        }
    }

    private mutating func update(_ id: String?, _ change: (inout C4Element) -> Void) {
        guard let index = output.workspace.elements.firstIndex(where: { $0.id == id }) else { return }
        change(&output.workspace.elements[index])
    }

    private mutating func element(
        _ kind: C4Element.Kind, identifier: String?, arguments: [String],
        opensBlock: Bool, line: Int, owner: String?
    ) {
        // Where each kind may appear, and what it then belongs to.
        let ownerKind = owner.flatMap(output.workspace.element)?.kind
        let allowed: Bool
        switch kind {
        case .person, .softwareSystem: allowed = ownerKind == nil
        case .container: allowed = ownerKind == .softwareSystem
        case .component: allowed = ownerKind == .container
        }
        guard allowed else {
            let home: String
            switch kind {
            case .person, .softwareSystem: home = "directly inside 'model'"
            case .container: home = "inside a softwareSystem"
            case .component: home = "inside a container"
            }
            error("A \(kind == .softwareSystem ? "softwareSystem" : kind.rawValue) has to be \(home)", line: line)
            if opensBlock { stack.append(.skipped) }
            return
        }
        guard let name = arguments.first, !name.isEmpty else {
            error("A \(kind.rawValue) needs a name in quotes", line: line)
            if opensBlock { stack.append(.skipped) }
            return
        }

        let id: String
        if let identifier {
            guard output.workspace.element(identifier) == nil else {
                error("The identifier '\(identifier)' is already used", line: line)
                if opensBlock { stack.append(.skipped) }
                return
            }
            id = identifier
        } else {
            // Elements without an identifier can still be drawn; nothing can
            // refer to them, so the name we give them never shows.
            generatedIDs += 1
            id = "_unnamed\(generatedIDs)"
        }

        // person / softwareSystem:  name [description] [tags]
        // container / component:    name [description] [technology] [tags]
        var element = C4Element(id: id, kind: kind, name: name, parent: owner, line: line)
        element.description = arguments.count > 1 && !arguments[1].isEmpty ? arguments[1] : nil
        let hasTechnology = kind == .container || kind == .component
        if hasTechnology, arguments.count > 2, !arguments[2].isEmpty {
            element.technology = arguments[2]
        }
        let tagIndex = hasTechnology ? 3 : 2
        if arguments.count > tagIndex {
            for tag in arguments[tagIndex].split(separator: ",") {
                element.tags.insert(tag.trimmingCharacters(in: .whitespaces))
            }
        }
        output.workspace.elements.append(element)
        if opensBlock { stack.append(.element(id)) }
    }

    private mutating func relationship(
        _ tokens: [Token], arrow: Int, opensBlock: Bool, line: Int, owner: String?
    ) {
        if opensBlock { stack.append(.skipped) }
        let source: String?
        if arrow == 0 {
            source = owner
        } else if case .word(let id) = tokens[0] {
            source = id
        } else {
            source = nil
        }
        guard let source else {
            error("A relationship needs something on the left of '->'", line: line)
            return
        }
        guard tokens.count > arrow + 1, case .word(let destination) = tokens[arrow + 1] else {
            error("A relationship needs an identifier on the right of '->'", line: line)
            return
        }
        let arguments = tokens[(arrow + 2)...].compactMap(\.text)
        pendingRelationships.append(C4Relationship(
            source: source, destination: destination,
            description: arguments.first.flatMap { $0.isEmpty ? nil : $0 },
            technology: arguments.count > 1 && !arguments[1].isEmpty ? arguments[1] : nil,
            line: line))
    }

    private mutating func resolveRelationships() {
        for relationship in pendingRelationships {
            let missing = [relationship.source, relationship.destination]
                .filter { output.workspace.element($0) == nil }
            if let unknown = missing.first {
                error("Nothing in the model is called '\(unknown)'", line: relationship.line)
            } else {
                output.workspace.relationships.append(relationship)
            }
        }
    }

    // MARK: - Views

    private mutating func viewsStatement(_ tokens: [Token], opensBlock: Bool, line: Int) {
        guard case .word(let rawKeyword)? = tokens.first else {
            if opensBlock { stack.append(.skipped) }
            return
        }
        let arguments = tokens.dropFirst().compactMap(\.text)
        let kind: C4View.Kind
        switch rawKeyword.lowercased() {
        case "systemlandscape": kind = .systemLandscape
        case "systemcontext": kind = .systemContext
        case "container": kind = .container
        case "styles", "theme", "themes", "branding", "terminology":
            if opensBlock { stack.append(.skipped) }
            if !notedStyles {
                notedStyles = true
                note("Styles and themes are not applied yet; the diagram uses the app's own look", line: line)
            }
            return
        case "properties", "configuration":
            if opensBlock { stack.append(.skipped) }
            return
        default:
            if opensBlock { stack.append(.skipped) }
            note("'\(rawKeyword)' views are not supported yet and were left out", line: line)
            return
        }

        var view = C4View(kind: kind, line: line)
        var rest = arguments[...]
        if kind != .systemLandscape {
            guard let scope = rest.first else {
                error("A \(rawKeyword) view needs the identifier of a software system", line: line)
                if opensBlock { stack.append(.skipped) }
                return
            }
            view.scope = scope
            rest = rest.dropFirst()
        }
        view.key = rest.first.flatMap { $0.isEmpty ? nil : $0 }
        output.workspace.views.append(view)
        if opensBlock { stack.append(.view(output.workspace.views.count - 1)) }
    }

    private mutating func viewStatement(_ tokens: [Token], opensBlock: Bool, line: Int, index: Int) {
        if opensBlock { stack.append(.skipped) }
        guard case .word(let rawKeyword)? = tokens.first else { return }
        let arguments = tokens.dropFirst().compactMap(\.text)
        switch rawKeyword.lowercased() {
        case "include":
            if arguments.contains("*") {
                output.workspace.views[index].includes = nil
            } else {
                output.workspace.views[index].includes =
                    (output.workspace.views[index].includes ?? []) + arguments
            }
        case "exclude":
            output.workspace.views[index].excludes += arguments
        case "title":
            output.workspace.views[index].title = arguments.first
        case "autolayout", "description", "default", "animation", "properties":
            // Layout is the renderer's job; the rest does not change the picture.
            break
        default:
            note("'\(rawKeyword)' is not supported in a view yet and was ignored", line: line)
        }
    }

    private mutating func checkViews() {
        var valid: [C4View] = []
        for view in output.workspace.views {
            if let scope = view.scope {
                guard let element = output.workspace.element(scope) else {
                    error("Nothing in the model is called '\(scope)'", line: view.line)
                    continue
                }
                guard element.kind == .softwareSystem else {
                    error("'\(scope)' is a \(element.kind.rawValue); this view needs a softwareSystem", line: view.line)
                    continue
                }
            }
            for id in (view.includes ?? []) + view.excludes where output.workspace.element(id) == nil {
                note("Nothing in the model is called '\(id)'; it was ignored in this view", line: view.line)
            }
            valid.append(view)
        }
        output.workspace.views = valid

        // A model with no views is still worth looking at.
        let hasErrors = output.diagnostics.containsError
        let hasSystems = output.workspace.elements.contains { $0.kind == .softwareSystem || $0.kind == .person }
        if valid.isEmpty, !hasErrors, hasSystems {
            output.workspace.views = [C4View(kind: .systemLandscape, line: 1)]
            note("No views are defined, so this shows a system landscape of the whole model", line: nil)
        }
    }
}
