# Chartz

Mermaid and C4 diagram editor for iPhone (including the foldable iPhone Duo),
iPad, Mac, Vision Pro and Apple TV. No watchOS. Native Swift renderer, no
JavaScript and no web view. README.md has the feature list and milestones.

## Layout

- `App/`: app lifecycle, file type, tvOS gallery.
- `Packages/DiagramKit/`: `DiagramCore` (no UI), `MermaidEngine`,
  `StructurizrEngine` (placeholder), `EditorUI` (SwiftUI).
- `Vendor/MermaidKit/`: the renderer. Vendored and owned by us, see
  `Vendor/MermaidKit/VENDORED.md`. Log every change to it there.
- `project.yml`: XcodeGen spec. The `.xcodeproj` and `App/Info.plist` are
  generated and gitignored; never commit them.

## Rules

- Only `Packages/DiagramKit/Sources/MermaidEngine` may import MermaidKit
  modules. Everything else goes through the `DiagramEngine` protocol.
- Apple TV is view-only. Guard editor code with `#if !os(tvOS)`.
- Layout decisions follow available width, not device checks.
- DiagramKit is in Swift 5 language mode for now.

## Building

The app needs Xcode on a Mac (`scripts/bootstrap.sh`, then open the project).
Cloud sessions are Linux: the app and `EditorUI` cannot be compiled there.
`MermaidLayout` inside `Vendor/MermaidKit` is platform-free, so if a Swift
toolchain is present, `swift build --target MermaidLayout` and its tests are
the things that can run. If nothing can be compiled, say so in the PR rather
than implying the change was built.

Milestone 1 has never been compiled. Treat compiler errors from the first Mac
build as expected work, not as regressions.
