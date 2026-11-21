// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NonSleep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NonSleep", targets: ["NonSleep"]),
        .executable(name: "NonSleepHelper", targets: ["NonSleepHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "NonSleepCore"),
        .executableTarget(name: "NonSleep", dependencies: ["NonSleepCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "NonSleepHelper", dependencies: ["NonSleepCore"]),
        .testTarget(name: "NonSleepCoreTests", dependencies: ["NonSleepCore"]),
        .testTarget(name: "NonSleepTests", dependencies: ["NonSleep"])
    ]
)
