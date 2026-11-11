// swift-tools-version:5.10
import PackageDescription

// Everything Plate decides (what a recipe needs, what you can cook, the plan, the shopping list) lives here as plain
// Swift with no iPhone frameworks, so it is tested on any machine, including GitHub's Linux runners.
let package = Package(
    name: "PlateCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PlateCore", targets: ["PlateCore"])],
    targets: [
        .target(name: "PlateCore"),
        .testTarget(name: "PlateCoreTests", dependencies: ["PlateCore"]),
    ]
)
