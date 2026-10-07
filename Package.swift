// swift-tools-version: 6.2
import Foundation
import PackageDescription

// El Info.plist se incrusta en el ejecutable para que los permisos (micrófono)
// funcionen también al lanzarlo desde Xcode o con `swift run`.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Info.plist")
    .path

let package = Package(
    name: "StepbroWhispr",
    platforms: [.macOS("27.0")],
    targets: [
        // Lógica pura (texto, diccionario, atajos, estilos, Groq): sin interfaz y con tests.
        .target(
            name: "StepbroWhisprCore",
            path: "Sources/StepbroWhisprCore"
        ),
        // La app: interfaz, audio y sistema.
        .executableTarget(
            name: "StepbroWhispr",
            dependencies: ["StepbroWhisprCore"],
            path: "Sources/StepbroWhispr",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ])
            ]
        ),
        .testTarget(
            name: "StepbroWhisprCoreTests",
            dependencies: ["StepbroWhisprCore"],
            path: "Tests/StepbroWhisprCoreTests"
        ),
    ]
)
