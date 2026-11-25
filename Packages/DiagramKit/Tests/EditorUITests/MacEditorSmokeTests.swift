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
