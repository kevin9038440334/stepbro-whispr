// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StepbroWhispr",
    platforms: [.macOS("27.0")],
    targets: [
        // Lógica pura (texto, diccionario, atajos, estilos, Groq): sin interfaz y con tests.
        .target(
            name: "StepbroWhisprCore",
            path: "Sources/StepbroWhisprCore"
        ),
        .testTarget(
            name: "StepbroWhisprCoreTests",
            dependencies: ["StepbroWhisprCore"],
            path: "Tests/StepbroWhisprCoreTests"
        ),
    ]
)
