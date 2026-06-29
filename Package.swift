// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "MiScaleCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v16),
    ],
    products: [
        .library(name: "MiScaleCore", targets: ["MiScaleCore"]),
    ],
    targets: [
        // Pure, platform-agnostic logic (parser + body-composition math).
        // No CoreBluetooth / HealthKit / UIKit imports — runnable with `swift test`
        // on a macOS CI runner with no simulator and no hardware.
        .target(name: "MiScaleCore"),
        .testTarget(name: "MiScaleCoreTests", dependencies: ["MiScaleCore"]),
    ]
)
