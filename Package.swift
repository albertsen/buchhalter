// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Buchhalter",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "BuchhalterCore", targets: ["BuchhalterCore"]),
        .executable(name: "buchhalter", targets: ["Buchhalter"]),
        .executable(name: "buchhalter-cli", targets: ["BuchhalterCLI"]),
    ],
    targets: [
        // Display-free core: model, store, operations and pure logic.
        .target(
            name: "BuchhalterCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Google Books key in the login keychain (Security), shared by
        // the app and the command line tool.
        .target(
            name: "BuchhalterKeychain",
            dependencies: ["BuchhalterCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Mac app. Every declaration is @MainActor by default.
        .executableTarget(
            name: "Buchhalter",
            dependencies: ["BuchhalterCore", "BuchhalterKeychain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        // `buchhalter-cli`: maintenance commands on the library (find-covers).
        .executableTarget(
            name: "BuchhalterCLI",
            dependencies: ["BuchhalterCore", "BuchhalterKeychain"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
            ]
        ),
        .testTarget(
            name: "BuchhalterCoreTests",
            dependencies: ["BuchhalterCore"],
            // The fixtures are read through #filePath, not as package resources.
            exclude: ["Fixtures"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
