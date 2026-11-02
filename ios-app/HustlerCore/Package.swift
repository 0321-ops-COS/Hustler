// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HustlerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "HustlerCore", targets: ["HustlerCore"]),
        .library(name: "HustlerArchive", targets: ["HustlerArchive"])
    ],
    dependencies: [
        // The only third-party dependency in the project: MIT, no transitive
        // dependencies on Apple platforms, pinned exactly. It is confined to
        // `HustlerArchive` so the calculations in `HustlerCore` stay Foundation-only.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "HustlerCore",
            path: "Sources/HustlerCore"
        ),
        .target(
            name: "HustlerArchive",
            dependencies: [
                "HustlerCore",
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/HustlerArchive"
        ),
        .testTarget(
            name: "HustlerCoreTests",
            dependencies: [
                "HustlerCore",
                "HustlerArchive",
                // Tests build their own ZIP fixtures with the same library; the
                // production code never writes an archive.
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Tests/HustlerCoreTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
