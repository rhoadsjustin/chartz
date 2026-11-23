import CoreGraphics
import DiagramCore
import Foundation
import MermaidLayout
import MermaidRender

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// `DiagramEngine` backed by our MermaidKit fork.
///
/// This file is the only place the app touches MermaidKit's API. Everything
/// else talks to `DiagramEngine`, so renderer changes in the fork stay local.
public struct MermaidDiagramEngine: DiagramEngine {
    public let format = DiagramFormat.mermaid

    public init() {}

    public func diagnose(_ source: String) -> [Diagnostic] {
        MermaidParser.diagnose(source).map { item in
            Diagnostic(
                severity: item.severity == .error ? .error : .note,
                line: item.line,
                message: item.message)
        }
    }

    public func render(_ source: String, options: RenderOptions) -> RenderedDiagram? {
        guard let image = MermaidRenderer.image(source: source, theme: theme(for: options)) else {
            return nil
        }
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return nil }
        return RenderedDiagram(image: cgImage, scale: image.scale)
        #elseif canImport(AppKit)
        guard image.size.width > 0 else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        return RenderedDiagram(image: cgImage, scale: CGFloat(cgImage.width) / image.size.width)
        #else
        return nil
        #endif
    }

    public func export(_ source: String, as kind: ExportKind, options: RenderOptions) -> Data? {
        let theme = theme(for: options)
        switch kind {
        case .png:
            return MermaidRenderer.pngData(source: source, theme: theme)
        case .pdf:
            return MermaidRenderer.pdfData(source: source, theme: theme)
        case .svg:
            return MermaidRenderer.svg(source: source, theme: theme).map { Data($0.utf8) }
        }
    }

    private func theme(for options: RenderOptions) -> DiagramTheme {
        DiagramTheme(prefersDark: options.prefersDark)
    }
}
