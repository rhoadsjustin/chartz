import Foundation

/// A diagram the presenter can show: one file from iCloud, or a built-in sample.
public struct LibraryDiagram: Identifiable, Hashable, Sendable {
    /// Stable across refreshes: the file's path, or `sample:` plus its name.
    public let id: String
    public let name: String
    public let format: DiagramFormat
    public let source: String
    public let modified: Date?

    public init(id: String, name: String, format: DiagramFormat, source: String, modified: Date? = nil) {
        self.id = id
        self.name = name
        self.format = format
        self.source = source
        self.modified = modified
    }
}

/// Finds and reads diagram files. No iCloud here: this works on any folder,
/// which is what makes it testable; the iCloud part only decides which folder.
public enum DiagramLibrary {
    public static let fileExtensions: Set<String> = ["mmd", "mermaid", "dsl"]

    public static func isDiagramFile(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Reads one file. Nil when it is not a diagram file, cannot be read, is
    /// not UTF-8, or is empty.
    public static func item(at url: URL) -> LibraryDiagram? {
        guard isDiagramFile(url),
              let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8),
              !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return LibraryDiagram(
            id: url.standardizedFileURL.path,
            name: url.deletingPathExtension().lastPathComponent,
            // The text decides; the extension only breaks ties.
            format: .detecting(source, fallback: DiagramFormat(fileExtension: url.pathExtension)),
            source: source,
            modified: values?.contentModificationDate)
    }

    /// Every diagram under `directory`, subfolders included, by name.
    public static func items(inDirectory directory: URL) -> [LibraryDiagram] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var items: [LibraryDiagram] = []
        for case let url as URL in enumerator {
            if let item = item(at: url) { items.append(item) }
        }
        return sorted(items)
    }

    public static func sorted(_ items: [LibraryDiagram]) -> [LibraryDiagram] {
        items.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    public static let sampleItems: [LibraryDiagram] = SampleDiagrams.all.map {
        LibraryDiagram(id: "sample:\($0.name)", name: $0.name, format: $0.format, source: $0.source)
    }
}

/// Where a presentation is: which diagram, and which of its views.
///
/// A value type with no UI, so stepping through a deck with a remote can be
/// tested without one.
public struct PresentationDeck: Equatable, Sendable {
    public private(set) var items: [LibraryDiagram]
    public private(set) var index = 0
    /// Position among the current diagram's views, for sources with several.
    public private(set) var viewIndex = 0

    public init(items: [LibraryDiagram] = []) {
        self.items = items
    }

    public var current: LibraryDiagram? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// "3 of 7", or nil when there is nothing to count.
    public var position: String? {
        items.count > 1 ? "\(index + 1) of \(items.count)" : nil
    }

    /// Moves to the next (`+1`) or previous (`-1`) diagram, wrapping round.
    public mutating func step(by offset: Int) {
        guard !items.isEmpty else { return }
        index = ((index + offset) % items.count + items.count) % items.count
        viewIndex = 0
    }

    /// Moves between the current diagram's views; stops at either end rather
    /// than wrapping, so "down" past the last view does nothing surprising.
    public mutating func stepView(by offset: Int, count: Int) {
        guard count > 0 else {
            viewIndex = 0
            return
        }
        viewIndex = min(max(viewIndex + offset, 0), count - 1)
    }

    public mutating func select(_ id: LibraryDiagram.ID) {
        guard let found = items.firstIndex(where: { $0.id == id }) else { return }
        if found != index { viewIndex = 0 }
        index = found
    }

    /// Swaps in a refreshed list (iCloud delivered a change) without losing
    /// the audience's place: stays on the same diagram if it still exists.
    public mutating func replaceItems(_ newItems: [LibraryDiagram]) {
        let currentID = current?.id
        items = newItems
        if let currentID, let found = newItems.firstIndex(where: { $0.id == currentID }) {
            index = found
        } else {
            index = min(index, max(newItems.count - 1, 0))
            viewIndex = 0
        }
    }
}
