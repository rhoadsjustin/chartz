# Chartz

Mermaid and C4 diagram editor for iPhone (including the foldable iPhone Duo),
iPad, Mac, Vision Pro and Apple TV. No watchOS. Native Swift renderer, no
JavaScript and no web view. README.md has the feature list and milestones.

## Layout

- `App/`: app lifecycle, file type, tvOS gallery.
- `Packages/DiagramKit/`: `DiagramCore` (no UI), `MermaidEngine`,
  `StructurizrEngine` (DSL to C4 model to Mermaid C4 text, drawn by
  `MermaidEngine`), `EditorUI` (SwiftUI).
- `Vendor/MermaidKit/`: the renderer. Vendored and owned by us, see
  `Vendor/MermaidKit/VENDORED.md`. Log every change to it there.
- `Config/`: build settings. `Signing.local.xcconfig` (gitignored) holds the
  user's team id and bundle prefix; never commit it or put a team id anywhere
  else.
- `project.yml`: XcodeGen spec. The `.xcodeproj` and `App/Info.plist` are
  generated and gitignored; never commit them.

## Rules

- Only `Packages/DiagramKit/Sources/MermaidEngine` may import MermaidKit
  modules. Everything else goes through the `DiagramEngine` protocol.
- Apple TV is view-only. Guard editor code with `#if !os(tvOS)`. The
  presenter views are deliberately not tvOS-only, so the Mac tests can host
  them.
- The app must keep building and running with no team and no iCloud. iCloud
  code treats "no container" as a normal state, not an error.
- Layout decisions follow size class and the shape of the space. No device
  checks, no width breakpoints, no `UIScreen.main`.
- Two-pane layouts on iOS go through `ArrangementView` so the Duo's fold is
  handled by the system. It is iOS 27.1 only: keep it behind `#if os(iOS)`
  and `#available`.
- Toolbar items are `Label`s with a title and a symbol, never text-only.
- `StructurizrEngine` never imports MermaidKit; it produces Mermaid source
  and calls `MermaidDiagramEngine`. Unknown DSL is skipped with a note
  diagnostic, never an error, so real-world workspaces still draw.
- The language comes from the text (`DiagramFormat.detecting`), not the file
  extension.
- `DiagramCore` has no UI imports. Editing rules that can be tested without
  a text view belong there.
- DiagramKit is in Swift 5 language mode for now.

## Building

The app needs Xcode on a Mac (`scripts/bootstrap.sh`, then open the project).
Cloud sessions are Linux: the app and `EditorUI` cannot be compiled there.
`MermaidLayout` inside `Vendor/MermaidKit` is platform-free, so if a Swift
toolchain is present, `swift build --target MermaidLayout` and its tests are
the things that can run. If nothing can be compiled, say so in the PR rather
than implying the change was built.

Milestones 1 to 5 build for iOS, macOS, tvOS and visionOS (Xcode 27.1) and
have been run on the iPhone Duo simulator only. The Apple TV presenter and
iCloud sync have never run on a TV or against iCloud. README.md "Build status"
lists what has been exercised; keep it current. Run `swift test` in
`Packages/DiagramKit` after any change there, and in `Vendor/MermaidKit`
after any change to the renderer (525 tests, about 30 seconds). Renderer
changes must land in both painters: `DiagramRenderer+X.swift` (CoreGraphics)
and `RenderScene+X.swift` (SVG), and in `DiagramScene+X.swift` if they draw
new text, or the conformance test fails.

Command-line build, after `scripts/bootstrap.sh`:

    xcodebuild -project Chartz.xcodeproj -scheme Chartz \
      -destination 'platform=iOS Simulator,name=iPhone Duo' \
      -derivedDataPath DerivedData build

Other destinations: `generic/platform=tvOS Simulator`,
`generic/platform=visionOS Simulator`, `platform=macOS`.
