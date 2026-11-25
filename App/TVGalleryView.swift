#if os(tvOS)
import EditorUI
import SwiftUI

/// Apple TV is a presenter, not an editor: the whole app is the library and
/// the full-screen presenter, both in `EditorUI`.
struct TVGalleryView: View {
    var body: some View {
        LibraryGalleryView()
    }
}
#endif
