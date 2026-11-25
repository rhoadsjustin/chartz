import DiagramCore
import Foundation
import MermaidEngine

/// `DiagramEngine` for a subset of the Structurizr DSL.
///
/// It parses the workspace into a C4 model (`StructurizrParser`), turns the
/// chosen view into Mermaid C4 source (`C4Lowering`) and hands that to the
/// Mermaid engine, so both languages are drawn by the same renderer.
public struct StructurizrDiagramEngine: DiagramEngine {
    public let format = DiagramFormat.structurizr
    private let renderer = MermaidDiagramEngine()

    public init() {}

    public func diagnose(_ source: String) -> [Diagnostic] {
        StructurizrParser.parse(source).diagnostics
    }

    public func views(in source: String) -> [DiagramViewInfo] {
        let parsed = StructurizrParser.parse(source)
        guard !parsed.diagnostics.containsError else { return [] }
        return parsed.workspace.views.enumerated().map { index, view in
            DiagramViewInfo(
                id: Self.id(of: view, at: index),
                name: C4Lowering.title(of: view, in: parsed.workspace))
        }
    }

    public func render(_ source: String, options: RenderOptions) -> RenderedDiagram? {
        mermaidSource(source, view: options.view).flatMap { renderer.render($0, options: options) }
    }

    public func export(_ source: String, as kind: ExportKind, options: RenderOptions) -> Data? {
        mermaidSource(source, view: options.view).flatMap {
            renderer.export($0, as: kind, options: options)
        }
    }

    /// The Mermaid C4 source for one view: the one with id `view`, or the
    /// first when that is nil or no longer exists. Nil when the workspace has
    /// errors or the view is empty.
    func mermaidSource(_ source: String, view: String?) -> String? {
        let parsed = StructurizrParser.parse(source)
        guard !parsed.diagnostics.containsError else { return nil }
        let views = parsed.workspace.views
        let chosen = views.enumerated().first { Self.id(of: $1, at: $0) == view }?.element ?? views.first
        return chosen.flatMap { C4Lowering.mermaid(for: $0, in: parsed.workspace) }
    }

    /// A view's key if it has one, else its position. Keys survive
    /// reordering; positions are the best a keyless view can do.
    private static func id(of view: C4View, at index: Int) -> String {
        view.key ?? "view-\(index + 1)"
    }
}
