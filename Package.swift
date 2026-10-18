// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MyOpenScaleCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v16),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "MyOpenScaleCore", targets: ["MyOpenScaleCore"]),
    ],
    targets: [
        // Pure, platform-agnostic logic (parser + body-composition math).
        // No CoreBluetooth / HealthKit / UIKit imports — runnable with `swift test`
        // on a macOS CI runner with no simulator and no hardware.
        .target(name: "MyOpenScaleCore"),
        .testTarget(name: "MyOpenScaleCoreTests", dependencies: ["MyOpenScaleCore"]),
    ]
)
