// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenContexts",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OpenContexts", targets: ["OpenContexts"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "OpenContextsCore"),
        .executableTarget(
            name: "OpenContexts",
            dependencies: ["OpenContextsCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "OpenContextsCoreTests", dependencies: ["OpenContextsCore"])
    ]
)
