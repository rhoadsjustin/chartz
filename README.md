# Chartz

A Mermaid and C4 diagram editor for iPhone (including the Duo), iPad, Mac,
Vision Pro and Apple TV. Diagrams are drawn by a native Swift renderer that we
own: a vendored copy of [MermaidKit](https://github.com/2389-research/MermaidKit)
(MIT) in `Vendor/MermaidKit`, with no JavaScript and no web view.

Milestones 1 (skeleton), 2 (editor polish), 3 (Structurizr DSL) and 4 (Apple
TV presenter) are in. The app builds for all
four destinations with Xcode 27.1 and has been run on the iPhone Duo simulator
in every posture. See "Build status" below for what has and has not been
exercised.

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

## What it does

- **One app target, four destinations**: iOS, macOS, visionOS, tvOS.
- **Document-based** on iPhone, iPad, Mac and Vision Pro. Files are plain text
  (`.mmd`, `.mermaid`, `.dsl`), opened in place, so they work from iCloud Drive
  or a repo checkout.
- **Code editor** on TextKit: syntax colouring, line numbers, Return keeps the
  current indent, and smart dashes and quotes are off so `-->` stays `-->`.
  Lines with a diagnostic get a coloured line number.
- **Vector preview.** The diagram is redrawn at the current zoom level, so it
  stays sharp. Pinch or use the buttons; zoom holds the centre.
- **Layout by size class and shape.** Compact width shows one pane with a
  Code/Preview switch. Regular width shows both: side by side when wider than
  tall, stacked when taller than wide. On a partly open Duo the panes sit
  either side of the fold.
- **Live render** 200ms after you stop typing, off the main thread. While the
  source is broken mid-edit the last good render stays on screen, dimmed.
- **Structurizr DSL**: a workspace's system landscape, system context and
  container views, drawn by the same renderer as Mermaid. A picker above the
  preview switches between views. See "Structurizr support" below.
- **The text decides the language.** A source that starts with `workspace` is
  Structurizr, whatever the file is called; anything else is Mermaid.
- **Templates** menu with eight starters. It asks before replacing source you
  have edited.
- **Diagnostics** under the code pane, with line numbers.
- **Export** to PNG, PDF and SVG.
- **Apple TV presenter**: a list of your diagrams with a live preview that
  follows the highlight; select one to present it full screen. Left and right
  move between diagrams, up and down between the views of a Structurizr
  workspace. Diagrams come from the app's iCloud folder once iCloud is set up
  (see "iCloud and signing"); the built-in samples are always listed.

## iCloud and signing

Out of the box the app builds with a placeholder bundle id and no iCloud, and
the Apple TV shows only the built-in samples. To sync your own diagrams:

```sh
cp Config/Signing.example.xcconfig Config/Signing.local.xcconfig
# edit it: your team id and a bundle prefix you own
scripts/bootstrap.sh
```

`Signing.local.xcconfig` is gitignored. It sets the development team, the
bundle prefix (the app becomes `<prefix>.chartz`, its container
`iCloud.<prefix>.chartz`) and turns on the iCloud Documents entitlement for
iPhone, iPad, Vision Pro and Apple TV. Xcode's automatic signing registers the
app id and container the first time you build for a device.

With that in place, the app's container shows up as a **Chartz** folder in
iCloud Drive, and new documents are saved there by default. Anything in that
folder (subfolders included) appears on an Apple TV signed in to the same
iCloud account, and updates when it is saved elsewhere.

The Mac is not included: iCloud there needs App Sandbox, which is still open.
Diagrams saved from a Mac reach the TV only if you put them in the Chartz
folder in iCloud Drive by hand.

## Layout

```
App/                         App lifecycle, file type, tvOS gallery
Packages/DiagramKit/
  Sources/DiagramCore/       Format, Diagnostic, DiagramEngine protocol, samples,
                             syntax scanner and editing rules (no UI)
  Sources/MermaidEngine/     The only code that calls MermaidKit
  Sources/StructurizrEngine/ DSL parser, C4 model, and lowering to Mermaid C4
  Sources/EditorUI/          Editor, code view, canvas, diagnostics, export
  Tests/                     DiagramCore, both engines, and a Mac editor smoke test
Vendor/MermaidKit/           The renderer: our vendored copy, see VENDORED.md
Config/                      Build settings; Signing.example.xcconfig for your team and iCloud
project.yml                  XcodeGen spec; the .xcodeproj is generated
scripts/bootstrap.sh
```

Everything outside `MermaidEngine` talks to the `DiagramEngine` protocol, so
changes inside the renderer never ripple into the UI.

## Structurizr support

The engine reads the workspace into a C4 model, turns the chosen view into
Mermaid C4 source, and hands that to the Mermaid engine.

Supported:

- `workspace`, `model`, `views`; `//`, `#` and `/* */` comments.
- `person`, `softwareSystem`, `container`, `component`, with name,
  description, technology and tags given in line or in the element's block.
  `group` and `enterprise` are read through.
- Relationships: `a -> b "Description" "Technology"`, and `-> b` inside an
  element.
- `systemLandscape`, `systemContext` and `container` views, with `include`,
  `exclude` and `title`. A model with no views gets a system landscape.
- The `External` tag draws a person or system as external; the `Database`
  tag (or a technology containing "database") marks a container as one.

Skipped with a note in the diagnostics, not rejected: `component`, `dynamic`,
`deployment` and `filtered` views, `styles` and themes, deployment
environments, hierarchical identifiers, and any other keyword it does not
know. Not handled at all: `!include`, `!extend` and multi-file workspaces.
`autoLayout` directions are ignored; the renderer picks its own layout.

Relationships are lifted to what a view shows: in a context view
`webApp -> otherSystem` is drawn as `thisSystem -> otherSystem`, and
relationships wholly inside one system are left out.

## Build status

Last checked 24 Nov 2026 with Xcode 27.1.

| Destination | Builds | Run |
| --- | --- | --- |
| iOS (iPhone Duo simulator) | yes | yes, closed, half open and open, both orientations, right-to-left and Reduce Transparency: editing, highlighting, line numbers, indent on Return, live render, diagnostics, templates, zoom, dark mode, autosave and reopen. Export was taken as far as the save sheet. |
| macOS | yes | not launched. An off-screen test builds the editor and checks the text view, ruler, colouring and indent. |
| tvOS simulator | yes | not run: no tvOS runtime installed on the build Mac. The presenter and gallery are hosted off screen on the Mac by tests, which is not the same as running on a TV. |
| visionOS simulator | yes | no visionOS runtime installed on the build Mac |

`swift test` inside `Packages/DiagramKit` runs 55 tests: the syntax scanner
and editing rules, format detection, every template through the real
renderer, all three export formats, the Structurizr parser and view lowering
(including every prefix of a workspace, as the editor sees while you type),
the diagram library (scanning a folder) and presentation deck, and off-screen
Mac smoke tests of the editor, the presenter and the gallery.

Still open:

- **iCloud sync has never run.** It needs a signed build with a real team
  and container, and a device or simulator signed in to iCloud; none of that
  exists on the build Mac. What is tested is the folder scanning, the deck,
  and that an unsigned build falls back to samples. The tvOS APIs used
  (`url(forUbiquityContainerIdentifier:)`, `NSMetadataQuery`,
  `startDownloadingUbiquitousItem`) are declared available on tvOS in the
  SDK headers; that they behave on a real Apple TV is unverified.
- **The Siri Remote has never been tried**: focus movement in the list,
  left/right/up/down in the presenter, and Menu to leave.

- **Signing.** Mac builds sign to run locally. Device builds and TestFlight
  need `Config/Signing.local.xcconfig`.
- **Mac sandbox.** The Mac build is unsandboxed for now. Before TestFlight,
  add App Sandbox with user-selected file read/write.
- **MermaidKit's own tests** have not been run against the vendored copy.
- **Fold handling is iOS only.** `ArrangementView` is in the iOS 27.1 SDK but
  not in the macOS, visionOS or tvOS 27.0 SDKs that ship with Xcode 27.1.
- **Folding or unfolding rebuilds the code view**, so the caret, scroll
  position and text-view undo stack are lost. The text is kept.
- **Not tried**: iPad, hardware keyboard, Dynamic Type sizes, very long
  documents, Split View beside another app, Picture in Picture.
- **Outer display in landscape with the keyboard up** leaves about five
  lines of code visible. It works; it is cramped.
- **Structurizr in the app** was tried on the Duo simulator with the built-in
  template only: both views render and the picker switches between them.
  Error reporting is covered by tests, not by hand.
- **A document keeps the extension it was created with.** Picking the
  Structurizr template in a new document leaves it saved as `.mmd`; it still
  opens as Structurizr because the text decides. There is no "new `.dsl`
  document" command yet.
- `duo-notes.md` records the iPhone Duo design pass and what is left of it.

## Renderer work we now own

Gaps in MermaidKit that matter for architecture diagrams, in rough priority:

- **C4 boundaries are flattened.** `System_Boundary`, `Container_Boundary` and
  deployment nodes keep their elements but lose the enclosing frame. This now
  shows in every Structurizr container view: the containers are drawn, the
  box around the system is not.
- **Styling is ignored**: `classDef`, `style`, `linkStyle`, `%%{init}`.
- **No hit-testing.** The platform-free `RenderScene` has geometry but no link
  back to source lines; tap-a-node-to-jump needs that.

## Milestones

1. Skeleton. Done.
2. Editor polish: TextKit editor with highlighting and line numbers, vector
   canvas, templates, fold-aware layouts for the Duo's half-open pose. Done.
3. Structurizr DSL subset: context and container views, lowered into the same
   renderer. Done.
4. Apple TV presenter with iCloud sync. Built; sync and the TV itself are
   unverified (see "Build status").
5. Renderer gaps above: C4 boundaries first, then styling.

## Naming

`com.example` is a placeholder bundle prefix. Set your own in
`Config/Signing.local.xcconfig`. The two `UTType` identifiers in
`App/DiagramFile.swift` and `project.yml` still say `com.example.chartz`;
change those by hand before shipping.
