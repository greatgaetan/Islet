// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Islet",
    // macOS 14, not 26. The original floor came from the author's machine, not
    // from an API — the whole project compiles for 14 unchanged. 13 would cost
    // 120 changes, almost all of them `@Observable`, which is load-bearing: it
    // is what makes the moment state changes, and therefore the moment springs
    // fire, something this code chooses rather than inherits.
    platforms: [.macOS("14.0")],
    targets: [
        // Pure logic: geometry, state machine, motion tokens.
        // No window, no view — runs and tests without launching a UI.
        .target(name: "IsletCore"),

        // AppKit shell + SwiftUI content.
        .executableTarget(name: "Islet", dependencies: ["IsletCore"]),

        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"]),
    ]
)
