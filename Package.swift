// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NonSleep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NonSleep", targets: ["NonSleep"]),
        .executable(name: "NonSleepHelper", targets: ["NonSleepHelper"])
    ],
    targets: [
        .target(name: "NonSleepCore"),
        .executableTarget(name: "NonSleep", dependencies: ["NonSleepCore"]),
        .executableTarget(name: "NonSleepHelper", dependencies: ["NonSleepCore"]),
        .testTarget(name: "NonSleepCoreTests", dependencies: ["NonSleepCore"]),
        .testTarget(name: "NonSleepTests", dependencies: ["NonSleep"])
    ]
)
