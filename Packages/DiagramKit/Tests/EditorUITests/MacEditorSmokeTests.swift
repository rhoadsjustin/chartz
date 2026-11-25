#if os(macOS)
import AppKit
import DiagramCore
import SwiftUI
import Testing
@testable import EditorUI

/// Hosts the real editor off screen on the Mac, where `swift test` runs.
/// It proves the AppKit code path builds its views and draws; it is not a
/// substitute for using the app.
@MainActor
@Suite struct MacEditorSmokeTests {
    private func host(_ source: String) -> NSHostingView<some View> {
        let view = NSHostingView(rootView: Harness(source: source))
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return view
    }

    private struct Harness: View {
        @State var source: String
        var body: some View {
            DiagramEditorView(source: $source, engine: DiagramEngines.engine(for: .mermaid))
        }
    }

    private func descendants<T: NSView>(of view: NSView, as type: T.Type) -> [T] {
        view.subviews.flatMap { child in
            (child as? T).map { [$0] } ?? [] + descendants(of: child, as: type)
        }
    }

    @Test func editorShowsTheSourceWithALineNumberRuler() async throws {
        let view = host(SampleDiagrams.flowchart.source)
        let textView = try #require(descendants(of: view, as: CodeNSTextView.self).first)
        #expect(textView.string == SampleDiagrams.flowchart.source)
        let ruler = try #require(textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)
        #expect(ruler.ruleThickness > 20)

        // Keywords are coloured, so the first word is not the plain text colour.
        let color = textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.systemPurple)

        // Give the debounced render time to land, then snapshot if asked to.
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()
        if let path = ProcessInfo.processInfo.environment["CHARTZ_SNAPSHOT"] {
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func returnKeepsIndentAndTabInsertsSpaces() throws {
        let view = host("flowchart TD\n    A --> B")
        let textView = try #require(descendants(of: view, as: CodeNSTextView.self).first)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertNewline(nil)
        #expect(textView.string == "flowchart TD\n    A --> B\n    ")
        textView.insertTab(nil)
        #expect(textView.string.hasSuffix("\n        "))
    }
}
#endif

#if os(macOS)
/// Hosts the presenter off screen. This is the only way it runs on the build
/// Mac, which has no tvOS simulator; it is not a substitute for a TV.
@MainActor
@Suite struct PresenterSmokeTests {
    private struct Harness: View {
        @State var deck: PresentationDeck
        var body: some View { PresenterView(deck: $deck) }
    }

    /// Draws the presenter into a bitmap and checks something was drawn.
    /// Set CHARTZ_PRESENTER_SNAPSHOT to a path to keep the picture.
    @Test func presenterDrawsTheCurrentDiagram() async throws {
        let view = NSHostingView(rootView: Harness(deck: PresentationDeck(items: DiagramLibrary.sampleItems)))
        view.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()

        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // A blank presenter is one flat colour; a drawn one is not.
        var colors = Set<String>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 16) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 16) {
                if let color = rep.colorAt(x: x, y: y) {
                    colors.insert("\(Int(color.redComponent * 255)),\(Int(color.greenComponent * 255)),\(Int(color.blueComponent * 255))")
                }
            }
        }
        #expect(colors.count > 3, "the presenter drew a single flat colour")

        if let path = ProcessInfo.processInfo.environment["CHARTZ_PRESENTER_SNAPSHOT"] {
            try #require(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func galleryBuildsAndFallsBackToSamplesWithoutICloud() async throws {
        let view = NSHostingView(rootView: LibraryGalleryView())
        view.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // The test bundle has no iCloud entitlement, which is exactly the
        // unsigned-build case: the model must settle on "unavailable".
        let model = DiagramLibraryModel()
        model.start()
        for _ in 0..<40 where model.cloudState == .checking {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.cloudState == .unavailable)
        #expect(model.cloudItems.isEmpty)
        #expect(model.allItems == DiagramLibrary.sampleItems)
    }
}
#endif
