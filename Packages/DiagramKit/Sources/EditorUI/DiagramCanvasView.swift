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
        let fit = Self.fitScale(diagram.size, in: container)
        #if os(tvOS)
        image(diagram, scale: fit)
            .frame(width: container.width, height: container.height)
        #else
        ScrollView([.horizontal, .vertical]) {
            image(diagram, scale: fit * zoom * pinch)
                .frame(minWidth: container.width, minHeight: container.height)
        }
        .gesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in
                    state = value.magnification
                }
                .onEnded { value in
                    zoom = Self.clamp(zoom * value.magnification)
                }
        )
        .overlay(alignment: .bottomTrailing) { zoomControls }
        #endif
    }

    private func image(_ diagram: RenderedDiagram, scale: CGFloat) -> some View {
        Image(decorative: diagram.image, scale: diagram.scale)
            .resizable()
            .interpolation(.high)
            .frame(width: diagram.size.width * scale, height: diagram.size.height * scale)
            .opacity(isStale ? 0.35 : 1)
    }

    #if !os(tvOS)
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoom = Self.clamp(zoom / 1.25)
            } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }
            Button {
                zoom = 1
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            Button {
                zoom = Self.clamp(zoom * 1.25)
            } label: {
                Label("Zoom in", systemImage: "plus.magnifyingglass")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(12)
    }
    #endif

    // MARK: - Geometry

    private static let margin: CGFloat = 16

    /// Scale that fits `size` inside `container` with a margin. Never scales up.
    static func fitScale(_ size: CGSize, in container: CGSize) -> CGFloat {
        let available = CGSize(
            width: max(container.width - margin * 2, 1),
            height: max(container.height - margin * 2, 1))
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(1, available.width / size.width, available.height / size.height)
    }

    static func clamp(_ zoom: CGFloat) -> CGFloat {
        min(max(zoom, 0.25), 8)
    }
}
