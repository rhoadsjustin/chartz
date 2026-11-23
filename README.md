# Chartz

A Mermaid and C4 diagram editor for iPhone (including the Duo), iPad, Mac,
Vision Pro and Apple TV. Diagrams are drawn by a native Swift renderer that we
own: a vendored copy of [MermaidKit](https://github.com/2389-research/MermaidKit)
(MIT) in `Vendor/MermaidKit`, with no JavaScript and no web view.

This is **milestone 1**: the multiplatform skeleton. It has not been compiled
yet. It was written on a machine without Xcode, against MermaidKit's source at
commit `8556a1b` (30 Oct 2026). Expect to fix a few compiler errors on first
build; see "First build" below for where they are most likely.

## Setup

Requires Xcode 26 or later (MermaidKit needs Swift 6.2) and XcodeGen.

```sh
brew install xcodegen
scripts/bootstrap.sh
open Chartz.xcodeproj
```

`bootstrap.sh` generates the Xcode project from `project.yml`. The renderer is
already in the repo, with tvOS added to its `Package.swift`; see
`Vendor/MermaidKit/VENDORED.md` for what was kept and changed.

## What milestone 1 does

- **One app target, four destinations**: iOS, macOS, visionOS, tvOS.
- **Document-based** on iPhone, iPad, Mac and Vision Pro. Files are plain text
  (`.mmd`, `.mermaid`, `.dsl`), opened in place, so they work from iCloud Drive
  or a repo checkout.
- **Editor**: code pane and live preview. Side by side when the view is 640pt
  or wider, tabs when narrower. It follows the width it is given, so it adapts
  to a folded or unfolded Duo, iPad Split View and Mac window resizing without
  device checks.
- **Live render** 200ms after you stop typing, off the main thread. While the
  source is broken mid-edit the last good render stays on screen, dimmed.
- **Diagnostics** under the code pane, with line numbers.
- **Pan and zoom** in the preview (pinch, or the corner buttons).
- **Export** to PNG, PDF and SVG.
- **Apple TV**: a view-only gallery of the built-in samples, to prove the
  renderer runs there.

## Layout

```
App/                         App lifecycle, file type, tvOS gallery
Packages/DiagramKit/
  Sources/DiagramCore/       Format, Diagnostic, DiagramEngine protocol, samples
  Sources/MermaidEngine/     The only code that calls MermaidKit
  Sources/StructurizrEngine/ Placeholder until milestone 3
  Sources/EditorUI/          Editor, canvas, diagnostics, export
  Tests/DiagramCoreTests/
Vendor/MermaidKit/           The renderer: our vendored copy, see VENDORED.md
project.yml                  XcodeGen spec; the .xcodeproj is generated
scripts/bootstrap.sh
```

Everything outside `MermaidEngine` talks to the `DiagramEngine` protocol, so
changes inside the renderer never ripple into the UI.

## First build: where to look if it fails

1. **tvOS in MermaidKit.** Upstream declares macOS, iOS, Mac Catalyst and
   visionOS only. Its renderer is CoreGraphics and UIKit, so tvOS should
   compile now that the platform is declared, but nobody has tried. Build the
   tvOS destination early; fixes go in `Vendor/MermaidKit`.
2. **`MermaidEngine/MermaidDiagramEngine.swift`.** It calls
   `MermaidParser.diagnose`, `MermaidRenderer.image`, `.pngData`, `.pdfData`
   and `.svg`. Signatures were read from the source, not compiled against it.
3. **`project.yml`.** If XcodeGen rejects it, the fallback is Xcode's
   "Multiplatform App" template: add `Packages/DiagramKit` as a local package,
   drop in the three files from `App/`, and copy the document and type
   declarations from `project.yml` into the target's Info tab.
4. **Mac sandbox.** The Mac build is unsandboxed for now. Before TestFlight,
   add App Sandbox with user-selected file read/write.

Unit tests for `DiagramCore` run with `swift test` inside `Packages/DiagramKit`.

## Renderer work we now own

Gaps in MermaidKit that matter for architecture diagrams, in rough priority:

- **C4 boundaries are flattened.** `System_Boundary`, `Container_Boundary` and
  deployment nodes keep their elements but lose the enclosing frame.
- **Styling is ignored**: `classDef`, `style`, `linkStyle`, `%%{init}`.
- **No hit-testing.** The platform-free `RenderScene` has geometry but no link
  back to source lines; tap-a-node-to-jump needs that.
- **Raster preview.** The preview is an image, so deep zoom gets soft. Drawing
  `RenderScene` in a SwiftUI `Canvas` fixes that and enables hit-testing.

## Milestones

1. Skeleton (this).
2. Editor polish: TextKit editor with highlighting and line numbers, vector
   canvas, templates, fold-aware layouts for the Duo's half-open pose.
3. Structurizr DSL subset: context and container views, lowered into the same
   renderer.
4. Apple TV presenter with iCloud sync.
5. Renderer gaps above: C4 boundaries first, then styling.

## Naming

`com.example` is a placeholder bundle prefix. To change it, edit `project.yml`
and the two `UTType` identifiers in `App/DiagramFile.swift`.
