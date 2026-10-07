// swift-tools-version:5.9
import PackageDescription

// WristBoxCore is the platform-independent heart of WristBox:
//   Motion layer  -> filtering, calibration, world-frame mapping
//   Gesture layer -> peak detection, classification, validation (anti-cheat)
//   Game layer    -> boxing engine, opponent AI, combos, counters, stamina
//   Progression   -> XP, coins, upgrades, career, daily challenges, persistence
//   Wire          -> messages exchanged between Watch and iPhone
//
// It only depends on Foundation, so it builds and tests on macOS, Linux and
// Windows toolchains as well as iOS/watchOS. No CoreMotion, no SwiftUI here.
let package = Package(
    name: "WristBoxCore",
    platforms: [.iOS(.v16), .watchOS(.v9), .macOS(.v13)],
    products: [
        .library(name: "WristBoxCore", targets: ["WristBoxCore"])
    ],
    targets: [
        .target(name: "WristBoxCore"),
        .testTarget(name: "WristBoxCoreTests", dependencies: ["WristBoxCore"])
    ]
)
