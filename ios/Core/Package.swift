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
        .library(name: "KvittaCore", targets: ["KvittaCore"])
    ],
    targets: [
        .target(name: "KvittaCore"),
        .testTarget(name: "KvittaCoreTests", dependencies: ["KvittaCore"])
    ]
)
