import DiagramCore
import SwiftUI

/// Shows a rendered diagram, fitted to the available space.
///
/// On iPhone, iPad, Mac and Vision Pro it pans and zooms (pinch, or the
/// buttons in the corner). On Apple TV it is fit-to-screen only.
public struct DiagramCanvasView: View {
    private let diagram: RenderedDiagram?
    private let isStale: Bool

    #if !os(tvOS)
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    #endif

    /// - Parameters:
    ///   - diagram: The diagram to show, or nil for the empty state.
    ///   - isStale: Dim the diagram because the source no longer renders and
    ///     this is the last version that did.
    public init(diagram: RenderedDiagram?, isStale: Bool = false) {
        self.diagram = diagram
        self.isStale = isStale
    }

    public var body: some View {
        GeometryReader { proxy in
            if let diagram, diagram.size.width > 0, diagram.size.height > 0 {
                content(diagram, in: proxy.size)
            } else {
                ContentUnavailableView(
                    "Nothing to draw yet",
                    systemImage: "rectangle.dashed",
                    description: Text("The preview appears once the source parses."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func content(_ diagram: RenderedDiagram, in container: CGSize) -> some View {
        #if os(tvOS)
        let fit = Self.fitScale(diagram.size, in: container)
        drawing(diagram, scale: fit)
            .frame(width: container.width, height: container.height)
        #else
        // The zoom controls get their own strip, so a fitted diagram is never
        // hidden underneath them.
        let area = CGSize(
            width: container.width, height: max(container.height - Self.controlsHeight, 1))
        let fit = Self.fitScale(diagram.size, in: area)
        ScrollView([.horizontal, .vertical]) {
            drawing(diagram, scale: fit * Self.clamp(zoom * pinch))
                .frame(minWidth: area.width, minHeight: area.height)
        }
        // Keep the middle of the diagram in the middle as it grows and
        // shrinks, instead of zooming out of the top-left corner.
        .defaultScrollAnchor(.center)
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    zoom = Self.clamp(zoom * value.magnification)
                }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            zoomControls.frame(maxWidth: .infinity, alignment: .trailing)
        }
        #endif
    }

    /// Redraws the diagram at `scale`, so zooming never magnifies pixels.
    private func drawing(_ diagram: RenderedDiagram, scale: CGFloat) -> some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)
            context.withCGContext { diagram.draw(in: $0) }
        }
        .frame(width: diagram.size.width * scale, height: diagram.size.height * scale)
        .opacity(isStale ? 0.35 : 1)
        .accessibilityElement()
        .accessibilityLabel("Diagram preview")
        .accessibilityAddTraits(.isImage)
    }

    #if !os(tvOS)
    private var zoomControls: some View {
        HStack(spacing: 0) {
            zoomButton("Zoom out", systemImage: "minus.magnifyingglass") {
                zoom = Self.clamp(zoom / 1.25)
            }
            zoomButton("Fit", systemImage: "arrow.up.left.and.arrow.down.right") {
                zoom = 1
            }
            zoomButton("Zoom in", systemImage: "plus.magnifyingglass") {
                zoom = Self.clamp(zoom * 1.25)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .frame(height: Self.controlsHeight)
    }

    /// Icon-only, padded out to a 44pt touch target.
    private func zoomButton(
        _ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
    #endif

    // MARK: - Geometry

    private static let margin: CGFloat = 16
    /// A 44pt row of zoom buttons with 8pt above and below.
    private static let controlsHeight: CGFloat = 60

    /// Scale that fits `size` inside `container` with a margin. Never scales up.
    static func fitScale(_ size: CGSize, in container: CGSize) -> CGFloat {
        let available = CGSize(
            width: max(container.width - margin * 2, 1),
            height: max(container.height - margin * 2, 1))
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, available.width / size.width, available.height / size.height)
    }

    static func clamp(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 0.25), 6)
    }
}
