import Combine
import DiagramCore
import Foundation

/// The presenter's list of diagrams: files from the app's iCloud container,
/// kept current as other devices save, plus the built-in samples.
///
/// iCloud needs the app to be signed with the iCloud Documents entitlement
/// (see `Config/Signing.example.xcconfig`). Without it, or when nobody is
/// signed in to iCloud, the container lookup returns nil and the model says
/// `unavailable`; the samples are always there.
@MainActor
public final class DiagramLibraryModel: ObservableObject {
    public enum CloudState: Equatable {
        /// Still asking the system where the container is.
        case checking
        /// No container: not signed in to iCloud, or the build has no entitlement.
        case unavailable
        /// Watching the container. `cloudItems` may still be empty.
        case ready
    }

    @Published public private(set) var cloudState = CloudState.checking
    @Published public private(set) var cloudItems: [LibraryDiagram] = []
    public let samples = DiagramLibrary.sampleItems

    /// iCloud diagrams first, then samples: the order a presentation runs in.
    public var allItems: [LibraryDiagram] { cloudItems + samples }

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    public init() {}

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    public func start() {
        guard !started else { return }
        started = true
        Task.detached(priority: .utility) { [weak self] in
            // Apple: this call can take a while and must not run on the main thread.
            let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            await self?.containerResolved(container)
        }
    }

    private func containerResolved(_ container: URL?) {
        guard container != nil else {
            cloudState = .unavailable
            return
        }
        cloudState = .ready

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: query, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.queryChanged() }
            })
        }
        self.query = query
        query.start()
    }

    private func queryChanged() {
        guard let query else { return }
        query.disableUpdates()
        var downloaded: [URL] = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  DiagramLibrary.isDiagramFile(url)
            else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                downloaded.append(url)
            } else {
                // Not on this device yet (always the case on a fresh Apple
                // TV). Ask for it; the query reports back when it lands.
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                if status == NSMetadataUbiquitousItemDownloadingStatusDownloaded {
                    // An older copy is here: show it while the new one arrives.
                    downloaded.append(url)
                }
            }
        }
        query.enableUpdates()

        Task.detached(priority: .userInitiated) { [weak self] in
            let items = Self.read(downloaded)
            await self?.publish(items)
        }
    }

    private func publish(_ items: [LibraryDiagram]) {
        if items != cloudItems { cloudItems = items }
    }

    /// Reads files through a coordinator, so a sync writing the same file
    /// cannot hand us half of it.
    private nonisolated static func read(_ urls: [URL]) -> [LibraryDiagram] {
        let coordinator = NSFileCoordinator()
        var items: [LibraryDiagram] = []
        for url in urls {
            var error: NSError?
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { readable in
                if let item = DiagramLibrary.item(at: readable) { items.append(item) }
            }
        }
        return DiagramLibrary.sorted(items)
    }
}
