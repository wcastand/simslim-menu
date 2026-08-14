// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimSlimMenu",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SimSlimMenu", targets: ["SimSlimMenu"])
    ],
    targets: [
        .executableTarget(
            name: "SimSlimMenu",
            path: "Sources"
        )
    ],
    swiftLanguageModes: [.v5]
)
