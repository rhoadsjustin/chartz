import Foundation

/// A named piece of example source: new-document starters, and the Apple TV
/// gallery until iCloud sync lands in milestone 4.
public struct SampleDiagram: Identifiable, Hashable, Sendable {
    public let name: String
    public let format: DiagramFormat
    public let source: String

    public var id: String { name }

    public init(name: String, format: DiagramFormat, source: String) {
        self.name = name
        self.format = format
        self.source = source
    }
}

public enum SampleDiagrams {
    /// What a brand-new document starts with.
    public static let starter = flowchart.source

    public static let all: [SampleDiagram] = [flowchart, sequence, c4Context, c4Container]

    public static let flowchart = SampleDiagram(
        name: "Flowchart",
        format: .mermaid,
        source: """
        flowchart TD
            A[Edit source] --> B{Parses?}
            B -->|Yes| C[Lay out]
            B -->|No| D[Show diagnostics]
            C --> E[Draw preview]
            D --> A
        """)

    public static let sequence = SampleDiagram(
        name: "Sequence",
        format: .mermaid,
        source: """
        sequenceDiagram
            participant Editor
            participant Engine
            participant Canvas
            Editor->>Engine: source text
            Engine-->>Editor: diagnostics
            Engine->>Canvas: rendered diagram
        """)

    public static let c4Context = SampleDiagram(
        name: "C4 Context",
        format: .mermaid,
        source: """
        C4Context
            title System Context
            Person(dev, "Developer", "Writes diagrams as code")
            System(app, "Diagram Editor", "Edits and renders Mermaid and C4")
            System_Ext(cloud, "iCloud Drive", "Stores diagram files")
            Rel(dev, app, "Edits diagrams in")
            Rel(app, cloud, "Syncs files to", "CloudKit")
        """)

    public static let c4Container = SampleDiagram(
        name: "C4 Container",
        format: .mermaid,
        source: """
        C4Container
            title Containers
            Person(dev, "Developer", "Writes diagrams as code")
            Container(ui, "Editor UI", "SwiftUI", "Code pane, preview, diagnostics")
            Container(core, "Diagram Core", "Swift", "Engine protocol and document model")
            Container(render, "Renderer", "Swift, CoreGraphics", "Parse, layout, draw")
            Rel(dev, ui, "Types source into")
            Rel(ui, core, "Asks for a render")
            Rel(core, render, "Delegates to")
        """)
}
