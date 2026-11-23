import DiagramCore
import EditorUI
import SwiftUI

@main
struct ChartzApp: App {
    var body: some Scene {
        #if os(tvOS)
        // Apple TV is a presenter, not an editor. Milestone 4 replaces the
        // built-in samples with diagrams synced over iCloud.
        WindowGroup {
            TVGalleryView()
        }
        #else
        DocumentGroup(newDocument: DiagramFile()) { file in
            DiagramEditorView(
                source: file.$document.source,
                engine: DiagramEngines.engine(for: file.document.format))
        }
        #endif
    }
}
