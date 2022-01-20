// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "PbRepository",
    platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
    products: [
        .library(
            name: "PbRepository",
            targets: ["PbRepository"]),
    ],
    dependencies: [
        .package(path: "../PbEssentials")
    ],
    targets: [
        .target(
            name: "PbRepository",
            dependencies: ["PbEssentials"]),
        .testTarget(
            name: "PbRepositoryTests",
            dependencies: ["PbEssentials", "PbRepository"]),
    ]
)
