// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Buchhalter",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "BuchhalterCore", targets: ["BuchhalterCore"]),
        .executable(name: "buchhalter", targets: ["Buchhalter"]),
    ],
    targets: [
        // Display-free core: model, store, operations and pure logic.
        .target(
            name: "BuchhalterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Mac app. Every declaration is @MainActor by default.
        .executableTarget(
            name: "Buchhalter",
            dependencies: ["BuchhalterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "BuchhalterCoreTests",
            dependencies: ["BuchhalterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
