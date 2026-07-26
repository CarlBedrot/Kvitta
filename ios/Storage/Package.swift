// swift-tools-version: 6.0
import PackageDescription

// GRDB stops here. `ios/Core` stays dependency-free so the money rules compile anywhere;
// this package is where the event log meets an actual disk.
let package = Package(
    name: "KvittaStorage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "KvittaStorage", targets: ["KvittaStorage"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "7.11.1"))
    ],
    targets: [
        .target(
            name: "KvittaStorage",
            dependencies: [
                .product(name: "KvittaCore", package: "Core"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "KvittaStorageTests",
            dependencies: [
                "KvittaStorage",
                .product(name: "KvittaCoreTestSupport", package: "Core")
            ]
        )
    ]
)
