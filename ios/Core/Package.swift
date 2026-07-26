// swift-tools-version: 6.0
import PackageDescription

// Deliberately zero dependencies: this package must compile anywhere, and the money
// logic in it is the one thing in the project that cannot afford a supply chain.
let package = Package(
    name: "KvittaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "KvittaCore", targets: ["KvittaCore"]),
        // Seeded generators for property tests. A library rather than test-target files so the
        // storage package can test against the same definition of "a valid history" — two copies
        // would drift, and the round-trip property is only meaningful if both sides agree.
        // The app never links this.
        .library(name: "KvittaCoreTestSupport", targets: ["KvittaCoreTestSupport"])
    ],
    targets: [
        .target(name: "KvittaCore"),
        .target(name: "KvittaCoreTestSupport", dependencies: ["KvittaCore"]),
        .testTarget(
            name: "KvittaCoreTests",
            dependencies: ["KvittaCore", "KvittaCoreTestSupport"]
        )
    ]
)
