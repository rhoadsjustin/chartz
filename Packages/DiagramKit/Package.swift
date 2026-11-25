// swift-tools-version: 6.0
import PackageDescription

// DiagramKit: everything the app needs that is not app-lifecycle code.
//
//   DiagramCore        Format, diagnostics and the DiagramEngine protocol. No UI.
//   MermaidEngine      DiagramEngine backed by our MermaidKit fork (Vendor/MermaidKit).
//   StructurizrEngine  Placeholder for the Structurizr DSL engine (milestone 3).
//   EditorUI           SwiftUI editor, preview canvas, diagnostics list, export.
//
// Swift 5 language mode keeps milestone 1 free of strict-concurrency churn.
// Flip to .v6 once the skeleton builds on every destination.
let package = Package(
    name: "DiagramKit",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],
    products: [
        .library(name: "DiagramCore", targets: ["DiagramCore"]),
        .library(name: "MermaidEngine", targets: ["MermaidEngine"]),
        .library(name: "StructurizrEngine", targets: ["StructurizrEngine"]),
        .library(name: "EditorUI", targets: ["EditorUI"]),
    ],
    dependencies: [
        // Our vendored copy of the renderer.
        .package(path: "../../Vendor/MermaidKit"),
    ],
    targets: [
        .target(name: "DiagramCore"),
        .target(
            name: "MermaidEngine",
            dependencies: [
                "DiagramCore",
                .product(name: "MermaidLayout", package: "MermaidKit"),
                .product(name: "MermaidRender", package: "MermaidKit"),
            ]),
        .target(name: "StructurizrEngine", dependencies: ["DiagramCore"]),
        .target(
            name: "EditorUI",
            dependencies: ["DiagramCore", "MermaidEngine", "StructurizrEngine"]),
        .testTarget(name: "DiagramCoreTests", dependencies: ["DiagramCore"]),
        .testTarget(name: "MermaidEngineTests", dependencies: ["DiagramCore", "MermaidEngine"]),
        .testTarget(name: "EditorUITests", dependencies: ["DiagramCore", "EditorUI"]),
    ],
    swiftLanguageModes: [.v5]
)
