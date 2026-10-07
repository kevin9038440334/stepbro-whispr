// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StepbroWhispr",
    platforms: [.macOS("27.0")],
    targets: [
        // Lógica pura de texto: sin interfaz.
        .target(
            name: "StepbroWhisprCore",
            path: "Sources/StepbroWhisprCore"
        ),
    ]
)
