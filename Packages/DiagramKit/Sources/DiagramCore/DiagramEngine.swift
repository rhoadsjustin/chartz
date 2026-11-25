import CoreGraphics
import Foundation

/// How a diagram should be drawn.
public struct RenderOptions: Hashable, Sendable {
    public var prefersDark: Bool
    /// Which of the source's views to draw, by `DiagramViewInfo.id`. Nil, or
    /// an id the source no longer has, means the first one.
    public var view: String?

    public init(prefersDark: Bool = false, view: String? = nil) {
        self.prefersDark = prefersDark
        self.view = view
    }
}

/// One picture a source can produce. Mermaid sources have exactly one and
/// report none; a Structurizr workspace has one per view it defines.
public struct DiagramViewInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A laid-out diagram, ready to draw at any scale.
///
/// It is a drawing, not a bitmap: the preview redraws it at the current zoom
/// level, so lines and text stay sharp however far in you go. Only
/// CoreGraphics types appear here, so this stays usable on every Apple
/// platform without importing UIKit or AppKit.
public struct RenderedDiagram: @unchecked Sendable {
    /// Natural size in points.
    public let size: CGSize
    /// The colour the diagram expects behind it, or nil for "whatever is there".
    public let background: CGColor?
    private let drawing: (CGContext) -> Void

    /// - Parameter draw: Draws the diagram with its top-left corner at the
    ///   origin of a y-down context. It must not fill the background, and must
    ///   be safe to call repeatedly.
    public init(size: CGSize, background: CGColor? = nil, draw: @escaping (CGContext) -> Void) {
        self.size = size
        self.background = background
        self.drawing = draw
    }

    public func draw(in context: CGContext) {
        drawing(context)
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

    /// The views `source` defines, in order. Empty when the language has no
    /// notion of views, or the source has only the one.
    func views(in source: String) -> [DiagramViewInfo]

    /// The drawn diagram, or nil when `source` cannot be rendered.
    func render(_ source: String, options: RenderOptions) -> RenderedDiagram?

    /// The diagram encoded as `kind`, or nil when it cannot be rendered or the
    /// engine does not support that kind.
    func export(_ source: String, as kind: ExportKind, options: RenderOptions) -> Data?
}

public extension DiagramEngine {
    func views(in source: String) -> [DiagramViewInfo] { [] }
}
