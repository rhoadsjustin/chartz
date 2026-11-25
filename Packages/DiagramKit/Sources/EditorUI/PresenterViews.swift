import DiagramCore
import SwiftUI

/// The Apple TV app: a list of diagrams on the left, the focused one on the
/// right. Select one to present it full screen.
///
/// Diagrams come from the app's iCloud folder, so saving on an iPhone, iPad
/// or Mac puts them on the TV; the built-in samples are always listed too.
/// Nothing here is tvOS-only except how you leave the presenter, so the Mac
/// test target can host it.
public struct LibraryGalleryView: View {
    @StateObject private var model = DiagramLibraryModel()
    @State private var deck = PresentationDeck(items: DiagramLibrary.sampleItems)
    @State private var isPresenting = false
    @FocusState private var focused: LibraryDiagram.ID?

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            List {
                Section("iCloud") { cloudRows }
                Section("Samples") { rows(model.samples) }
            }
            .frame(width: Self.listWidth)

            preview
        }
        .task { model.start() }
        .onChange(of: model.cloudItems) { _, _ in
            deck.replaceItems(model.allItems)
        }
        .onChange(of: focused) { _, id in
            // The preview follows the highlight; nothing needs pressing.
            if let id { deck.select(id) }
        }
        .presenterCover(isPresented: $isPresenting) {
            PresenterView(deck: $deck)
        }
    }

    #if os(tvOS)
    private static let listWidth: CGFloat = 560
    private static let previewPadding: CGFloat = 60
    #else
    private static let listWidth: CGFloat = 280
    private static let previewPadding: CGFloat = 24
    #endif

    @ViewBuilder
    private var cloudRows: some View {
        switch model.cloudState {
        case .checking:
            Label("Looking for iCloud", systemImage: "icloud")
                .foregroundStyle(.secondary)
        case .unavailable:
            Label(
                "Sign in to iCloud on this device to see your own diagrams here.",
                systemImage: "icloud.slash")
                .foregroundStyle(.secondary)
        case .ready where model.cloudItems.isEmpty:
            Label(
                "No diagrams yet. Save one to iCloud Drive, in the Chartz folder, from your iPhone, iPad or Mac.",
                systemImage: "icloud")
                .foregroundStyle(.secondary)
        case .ready:
            rows(model.cloudItems)
        }
    }

    private func rows(_ items: [LibraryDiagram]) -> some View {
        ForEach(items) { item in
            Button {
                deck.select(item.id)
                isPresenting = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                    Text(item.format.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .focused($focused, equals: item.id)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let item = deck.current {
            DiagramViewerView(source: item.source, engine: DiagramEngines.engine(for: item.format))
                .padding(Self.previewPadding)
        } else {
            ContentUnavailableView("No diagram selected", systemImage: "rectangle.dashed")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One diagram, full screen. Left and right move between diagrams; up and
/// down move between the views of a diagram that has several.
public struct PresenterView: View {
    @Binding private var deck: PresentationDeck
    @Environment(\.dismiss) private var dismiss
    @FocusState private var hasFocus: Bool

    public init(deck: Binding<PresentationDeck>) {
        self._deck = deck
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let item = deck.current {
                let engine = DiagramEngines.engine(for: item.format)
                let views = engine.views(in: item.source)
                let view = views.indices.contains(deck.viewIndex) ? views[deck.viewIndex] : views.first
                DiagramViewerView(source: item.source, engine: engine, view: view?.id)
                    .padding(Self.padding)
                    // A new identity per diagram, so one never shows through
                    // while the next is being laid out.
                    .id(item.id)
                caption(for: item, view: view, viewCount: views.count)
                    .padding(.bottom, Self.padding / 2)
            } else {
                ContentUnavailableView("Nothing to present", systemImage: "rectangle.dashed")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .focusable()
        .focused($hasFocus)
        .onAppear { hasFocus = true }
        #if os(tvOS) || os(macOS)
        .onMoveCommand(perform: move)
        .onExitCommand { dismiss() }
        #endif
    }

    #if os(tvOS)
    private static let padding: CGFloat = 80
    #else
    private static let padding: CGFloat = 32
    #endif

    private func caption(for item: LibraryDiagram, view: DiagramViewInfo?, viewCount: Int) -> some View {
        var parts = [item.name]
        if viewCount > 1, let view {
            parts.append("\(view.name) (view \(deck.viewIndex + 1) of \(viewCount))")
        }
        if let position = deck.position { parts.append(position) }
        return Text(parts.joined(separator: "  ·  "))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .accessibilityAddTraits(.updatesFrequently)
    }

    #if os(tvOS) || os(macOS)
    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: deck.step(by: -1)
        case .right: deck.step(by: 1)
        case .up: stepView(by: -1)
        case .down: stepView(by: 1)
        @unknown default: break
        }
    }

    private func stepView(by offset: Int) {
        guard let item = deck.current else { return }
        let count = DiagramEngines.engine(for: item.format).views(in: item.source).count
        deck.stepView(by: offset, count: count)
    }
    #endif
}

private extension View {
    /// Full screen where the platform has it; a sheet on the Mac.
    @ViewBuilder
    func presenterCover<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }
}
