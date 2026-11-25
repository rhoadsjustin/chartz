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
                // The text decides the language; the file type is only the
                // fallback for an empty document.
                engine: DiagramEngines.engine(
                    forSource: file.document.source, fallback: file.document.format))
        }
        #endif
    }
}
