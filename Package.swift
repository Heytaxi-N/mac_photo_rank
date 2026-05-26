// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PhotoTransfer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PhotoTransferCore", targets: ["PhotoTransferCore"]),
        .executable(name: "PhotoTransferApp", targets: ["PhotoTransferApp"])
    ],
    targets: [
        .target(
            name: "PhotoTransferCore",
            path: "Sources/PhotoTransferCore"
        ),
        .executableTarget(
            name: "PhotoTransferApp",
            dependencies: ["PhotoTransferCore"],
            path: "Sources/PhotoTransferApp"
        ),
        .executableTarget(
            name: "PhotoTransferCoreTestRunner",
            dependencies: ["PhotoTransferCore"],
            path: "Tests/PhotoTransferCoreTestRunner"
        )
    ]
)
