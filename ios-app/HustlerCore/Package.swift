// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HustlerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "HustlerCore", targets: ["HustlerCore"])
    ],
    targets: [
        .target(
            name: "HustlerCore",
            path: "Sources/HustlerCore"
        ),
        .testTarget(
            name: "HustlerCoreTests",
            dependencies: ["HustlerCore"],
            path: "Tests/HustlerCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
