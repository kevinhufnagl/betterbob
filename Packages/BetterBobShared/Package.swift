// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BetterBobShared",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
    ],
    products: [
        .library(name: "BetterBobShared", targets: ["BetterBobShared"])
    ],
    targets: [
        .target(
            name: "BetterBobShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
