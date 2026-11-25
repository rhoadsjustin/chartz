import DiagramCore
import Foundation
import MermaidEngine
import StructurizrEngine

/// Picks the engine for a source language.
public enum DiagramEngines {
    public static func engine(for format: DiagramFormat) -> any DiagramEngine {
        switch format {
        case .mermaid: return MermaidDiagramEngine()
        case .structurizr: return StructurizrDiagramEngine()
        }
    }

    /// The engine for `source`, going by what the text is rather than what
    /// the file is called. `fallback` decides when the text does not say.
    public static func engine(forSource source: String, fallback: DiagramFormat) -> any DiagramEngine {
        engine(for: DiagramFormat.detecting(source, fallback: fallback))
    }
}

/// What one pass over the source produced.
public struct RenderResult: Sendable {
    public var diagram: RenderedDiagram?
    public var diagnostics: [Diagnostic]
    /// The views the source defines; empty unless there is a choice to make.
    public var views: [DiagramViewInfo]

    public init(
        diagram: RenderedDiagram? = nil, diagnostics: [Diagnostic] = [],
        views: [DiagramViewInfo] = []
    ) {
        self.diagram = diagram
        self.diagnostics = diagnostics
        self.views = views
    }
}

/// Runs an engine off the main thread so typing never waits on layout.
public enum RenderPipeline {
    /// How long the editor waits after the last keystroke before re-rendering.
    public static let debounce: Duration = .milliseconds(200)

    public static func run(
        source: String,
        engine: any DiagramEngine,
        options: RenderOptions
    ) async -> RenderResult {
        await Task.detached(priority: .userInitiated) {
            RenderResult(
                diagram: engine.render(source, options: options),
                diagnostics: engine.diagnose(source),
                views: engine.views(in: source))
        }.value
    }
}

/// Identity for `.task(id:)`: re-render when the source or the options change.
struct RenderKey: Hashable {
    let source: String
    let format: DiagramFormat
    let options: RenderOptions
}
