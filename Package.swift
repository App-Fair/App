// swift-tools-version:5.5
import PackageDescription
import Darwin
import class Foundation.ProcessInfo

/// true when we are running from Xcode; false for a fair-ground release
let runningInXcode = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] == "com.apple.dt.Xcode"

let package = Package(
    name: "App",
    defaultLocalization: "en",
    platforms: [ .macOS(.v12), .iOS(.v15) ],
    products: [ .library(name: "App", type: .dynamic, targets: ["App"]) ],
    dependencies: [
        // the Fair main branch must be the *first* dependency
        .package(name: "Fair", url: "https://fair-ground.org/Fair.git", .branch("main")),
        // additional GitHub-hosted dependencies can be added below
    ],
    targets: [
        .target(name: "App", dependencies: [
            .product(name: "FairApp", package: "Fair"),
            .product(name: "FairExpo", package: "Fair"),
            .product(name: "FairKit", package: "Fair"),
        ], resources: [.process("Resources"), .copy("Bundle")]),
        .testTarget(name: "AppTests", dependencies: ["App"]),
    ]
)

