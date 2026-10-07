// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DragonCodexBoot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DragonCodexBoot", targets: ["DragonCodexBoot"])],
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "DragonCodexBoot", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"])
    ],
    swiftLanguageVersions: [.v5]
)
