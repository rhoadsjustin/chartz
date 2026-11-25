#if canImport(AppKit) || canImport(UIKit)
import CoreGraphics
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MermaidLayout

// Chartz addition (not upstream): see VENDORED.md.

/// A laid-out diagram that can be drawn into any `CGContext` at any scale.
///
/// Layout runs once, when the value is made. `draw` only strokes and fills,
/// so a host can redraw at a new zoom level without laying out again and
/// without the softness of scaling a bitmap.
public struct VectorDiagram: @unchecked Sendable {
    /// Canvas size in points, padding included.
    public let size: CGSize
    /// The theme's background, resolved for the theme's light or dark variant.
    public let canvasColor: CGColor
    private let prefersDark: Bool
    private let origin: CGPoint
    private let plan: (CGContext) -> Void

    init(size: CGSize, canvasColor: CGColor, origin: CGPoint, prefersDark: Bool,
         plan: @escaping (CGContext) -> Void) {
        self.size = size
        self.canvasColor = canvasColor
        self.origin = origin
        self.prefersDark = prefersDark
        self.plan = plan
    }

    /// Draws the diagram with its top-left corner at the context's origin.
    ///
    /// The context must be y-down (top-left origin), which is what SwiftUI's
    /// `Canvas` and `UIGraphicsImageRenderer` hand out. The background is not
    /// filled; the caller owns that.
    public func draw(in context: CGContext) {
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        // Pin appearance like the raster and PDF paths do, so dynamic
        // platform colors resolve to the theme's variant, not the ambient one.
        #if os(macOS)
        if let appearance = NSAppearance(named: prefersDark ? .darkAqua : .aqua) {
            appearance.performAsCurrentDrawingAppearance { plan(context) }
        } else {
            plan(context)
        }
        #else
        UITraitCollection(userInterfaceStyle: prefersDark ? .dark : .light)
            .performAsCurrent { plan(context) }
        #endif
        context.restoreGState()
    }
}

extension MermaidRenderer {
    /// Lays out `source` and returns it as a resolution-independent drawing,
    /// or nil when the source does not parse or the diagram is implausibly
    /// large. Shares the layout and draw plan with the raster and PDF paths.
    public static func vectorDiagram(source: String, theme: DiagramTheme,
                                     spacing: DiagramSpacing = .regular) -> VectorDiagram? {
        guard let (diagram, metadata) = MermaidParser.parseWithMetadata(source) else { return nil }
        let plan = DiagramRenderer.captionedPlan(
            DiagramRenderer.renderPlan(for: diagram, theme: theme, spacing: spacing),
            caption: metadata.title, diagram: diagram, theme: theme, textScale: spacing.textScale)
        guard let (canvasSize, originX, originY) =
                DiagramRenderer.paddedCanvas(size: plan.size, edgePolylines: plan.edgePolylines)
        else { return nil }
        return VectorDiagram(
            size: canvasSize, canvasColor: canvasColor(of: theme),
            origin: CGPoint(x: originX, y: originY),
            prefersDark: theme.prefersDark, plan: plan.draw)
    }

    /// The theme's canvas colour, resolved for the theme's own light or dark
    /// variant rather than whatever appearance happens to be current.
    private static func canvasColor(of theme: DiagramTheme) -> CGColor {
        var color = resolvedCGColor(theme.canvas)
        #if os(macOS)
        NSAppearance(named: theme.prefersDark ? .darkAqua : .aqua)?
            .performAsCurrentDrawingAppearance { color = resolvedCGColor(theme.canvas) }
        #else
        UITraitCollection(userInterfaceStyle: theme.prefersDark ? .dark : .light)
            .performAsCurrent { color = resolvedCGColor(theme.canvas) }
        #endif
        return color
    }
}
#endif
