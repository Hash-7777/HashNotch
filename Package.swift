// swift-tools-version: 6.0
import PackageDescription

// HashNotch is deliberately split into small, independent modules.
//
//   HashNotchKit   the core: notch window, HUD layout, and the NotchFeature
//                  plugin contract. It knows nothing about any concrete feature.
//   Feature*       one self-contained module per feature. Each depends only on
//                  HashNotchKit — never on another feature.
//   HashNotch      the executable. The ONLY place features are wired together
//                  (see Sources/HashNotch/FeatureManifest.swift).
//
// To add a feature: add a `Feature<Name>` target below, depend on it from the
// `HashNotch` target, and register it in FeatureManifest. Nothing in
// HashNotchKit ever needs to change.
let package = Package(
    name: "HashNotch",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "HashNotch", targets: ["HashNotch"])
    ],
    targets: [
        .target(name: "HashNotchKit"),

        .target(name: "FeatureNetwork", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureBattery", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureThermal", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureTokens", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureMedia", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureActivities", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureTimer", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureDownloads", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureAway", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureAirPods", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureCall", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureStorage", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureCPU", dependencies: ["HashNotchKit"]),
        .target(name: "FeatureMemory", dependencies: ["HashNotchKit"]),

        .executableTarget(
            name: "HashNotch",
            dependencies: [
                "HashNotchKit",
                "FeatureNetwork",
                "FeatureBattery",
                "FeatureThermal",
                "FeatureTokens",
                "FeatureMedia",
                "FeatureActivities",
                "FeatureTimer",
                "FeatureDownloads", "FeatureAway",
                "FeatureAirPods", "FeatureCall",
                "FeatureStorage",
                "FeatureCPU",
                "FeatureMemory",
            ]
        ),

        // Lightweight, framework-free checks so the core can be verified with
        // `swift run HashNotchChecks` even on a machine that only has the
        // Command Line Tools (no XCTest/Swift Testing). Swap for a proper
        // .testTarget once full Xcode is available.
        .executableTarget(
            name: "HashNotchChecks",
            dependencies: ["HashNotchKit", "FeatureMedia", "FeatureActivities", "FeatureTokens", "FeatureBattery", "FeatureDownloads", "FeatureAway", "FeatureAirPods", "FeatureCall", "FeatureNetwork", "FeatureStorage", "FeatureThermal", "FeatureCPU", "FeatureMemory", "FeatureTimer"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
