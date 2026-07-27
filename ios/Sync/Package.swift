// swift-tools-version: 6.0
import PackageDescription

// The only package that knows a network exists. Everything below it — Core's money rules,
// Storage's log — works exactly the same whether this is present, enabled, or unreachable.
let package = Package(
    name: "KvittaSync",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "KvittaSync", targets: ["KvittaSync"])
    ],
    dependencies: [
        .package(path: "../Core"),
        .package(path: "../Storage")
    ],
    targets: [
        .target(
            name: "KvittaSync",
            dependencies: [
                .product(name: "KvittaCore", package: "Core"),
                .product(name: "KvittaStorage", package: "Storage")
            ]
        ),
        .testTarget(
            name: "KvittaSyncTests",
            dependencies: [
                "KvittaSync",
                .product(name: "KvittaCoreTestSupport", package: "Core")
            ]
        )
    ]
)
