#if os(tvOS)
import DiagramCore
import EditorUI
import SwiftUI

/// Apple TV: pick a diagram on the left, see it full height on the right.
struct TVGalleryView: View {
    @State private var selection: SampleDiagram = SampleDiagrams.flowchart

    var body: some View {
        HStack(spacing: 0) {
            List(SampleDiagrams.all) { sample in
                Button(sample.name) {
                    selection = sample
                }
            }
            .frame(width: 460)

            DiagramViewerView(
                source: selection.source,
                engine: DiagramEngines.engine(for: selection.format))
                .padding(60)
        }
    }
}
#endif
