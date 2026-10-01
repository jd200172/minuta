// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Minuta",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Minuta",
            path: "Sources/Minuta",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MinutaTests",
            dependencies: ["Minuta"],
            path: "Tests/MinutaTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
