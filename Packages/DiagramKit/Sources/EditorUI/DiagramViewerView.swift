import DiagramCore
import SwiftUI

/// Read-only view of one diagram: renders `source` and shows it.
/// Used by the Apple TV gallery; also handy for thumbnails and Quick Look later.
public struct DiagramViewerView: View {
    private let source: String
    private let engine: any DiagramEngine

    @Environment(\.colorScheme) private var colorScheme
    @State private var result = RenderResult()

    public init(source: String, engine: any DiagramEngine) {
        self.source = source
        self.engine = engine
    }

    private var options: RenderOptions {
        RenderOptions(prefersDark: colorScheme == .dark)
    }

    public var body: some View {
        DiagramCanvasView(diagram: result.diagram)
            .task(id: RenderKey(source: source, format: engine.format, options: options)) {
                let fresh = await RenderPipeline.run(source: source, engine: engine, options: options)
                guard !Task.isCancelled else { return }
                result = fresh
            }
    }
}
