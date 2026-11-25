import DiagramCore
import SwiftUI

/// Read-only view of one diagram: renders `source` and shows it, fitted to
/// the space. Used by the presenter; also handy for thumbnails later.
public struct DiagramViewerView: View {
    private let source: String
    private let engine: any DiagramEngine
    private let view: String?

    @Environment(\.colorScheme) private var colorScheme
    @State private var result = RenderResult()

    /// - Parameter view: Which view of a multi-view source to show, by
    ///   `DiagramViewInfo.id`. Nil shows the first.
    public init(source: String, engine: any DiagramEngine, view: String? = nil) {
        self.source = source
        self.engine = engine
        self.view = view
    }

    private var options: RenderOptions {
        RenderOptions(prefersDark: colorScheme == .dark, view: view)
    }

    public var body: some View {
        DiagramCanvasView(diagram: result.diagram, allowsZoom: false)
            .task(id: RenderKey(source: source, format: engine.format, options: options)) {
                let fresh = await RenderPipeline.run(source: source, engine: engine, options: options)
                guard !Task.isCancelled else { return }
                result = fresh
            }
    }
}
