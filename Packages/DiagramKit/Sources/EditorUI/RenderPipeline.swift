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
}

/// What one pass over the source produced.
public struct RenderResult: Sendable {
    public var diagram: RenderedDiagram?
    public var diagnostics: [Diagnostic]

    public init(diagram: RenderedDiagram? = nil, diagnostics: [Diagnostic] = []) {
        self.diagram = diagram
        self.diagnostics = diagnostics
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
                diagnostics: engine.diagnose(source))
        }.value
    }
}

/// Identity for `.task(id:)`: re-render when the source or the options change.
struct RenderKey: Hashable {
    let source: String
    let options: RenderOptions
}
