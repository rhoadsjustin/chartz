import CoreGraphics
import Foundation

/// How a diagram should be drawn.
public struct RenderOptions: Hashable, Sendable {
    public var prefersDark: Bool

    public init(prefersDark: Bool = false) {
        self.prefersDark = prefersDark
    }
}

/// A rasterised diagram. `CGImage` keeps this type usable on every Apple
/// platform without importing UIKit or AppKit.
///
/// Milestone 2 replaces this with a vector scene drawn in a SwiftUI `Canvas`,
/// so zooming stays sharp and nodes become hit-testable.
public struct RenderedDiagram: @unchecked Sendable {
    public let image: CGImage
    /// Pixels per point.
    public let scale: CGFloat

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale > 0 ? scale : 1
    }

    /// Natural size in points.
    public var size: CGSize {
        CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }
}

/// File formats a diagram can be exported to.
public enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case png, pdf, svg

    public var id: String { rawValue }
    public var fileExtension: String { rawValue }
    public var displayName: String { rawValue.uppercased() }
}

/// A parser + layout + renderer for one source language.
///
/// Engines must be safe to call off the main thread: the editor renders in a
/// detached task so typing never waits on layout.
public protocol DiagramEngine: Sendable {
    var format: DiagramFormat { get }

    /// Problems in `source`. Empty means it parsed cleanly.
    func diagnose(_ source: String) -> [Diagnostic]

    /// The drawn diagram, or nil when `source` cannot be rendered.
    func render(_ source: String, options: RenderOptions) -> RenderedDiagram?

    /// The diagram encoded as `kind`, or nil when it cannot be rendered or the
    /// engine does not support that kind.
    func export(_ source: String, as kind: ExportKind, options: RenderOptions) -> Data?
}
