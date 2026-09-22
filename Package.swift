// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenContexts",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenContexts", targets: ["OpenContexts"])],
    targets: [
        .target(name: "OpenContextsCore"),
        .executableTarget(name: "OpenContexts", dependencies: ["OpenContextsCore"]),
        .testTarget(name: "OpenContextsCoreTests", dependencies: ["OpenContextsCore"])
    ]
)
