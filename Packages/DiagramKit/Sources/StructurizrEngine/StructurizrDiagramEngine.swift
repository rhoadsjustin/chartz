import DiagramCore
import Foundation

/// Placeholder for the Structurizr DSL engine (milestone 3).
///
/// Plan: parse `workspace { model { ... } views { ... } }` into a C4 model,
/// then lower each view into the same diagram types our MermaidKit fork
/// already lays out and draws, so both languages share one renderer.
public struct StructurizrDiagramEngine: DiagramEngine {
    public let format = DiagramFormat.structurizr

    public init() {}

    public func diagnose(_ source: String) -> [Diagnostic] {
        [Diagnostic(
            severity: .note,
            line: nil,
            message: "Structurizr DSL rendering is not built yet (milestone 3). The file is still editable.")]
    }

    public func render(_ source: String, options: RenderOptions) -> RenderedDiagram? {
        nil
    }

    public func export(_ source: String, as kind: ExportKind, options: RenderOptions) -> Data? {
        nil
    }
}
