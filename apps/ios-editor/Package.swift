// swift-tools-version: 5.10
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "NeonixEditor",
    platforms: [.iOS("17.0")],
    products: [
        .iOSApplication(
            name: "NeonixEditor",
            targets: ["AppModule"],
            bundleIdentifier: "com.neonix.editor",
            teamIdentifier: nil,
            displayVersion: "1.0",
            bundleVersion: "1",
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [.phone],
            supportedInterfaceOrientations: [.portrait]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/AppModule",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AppModuleTests",
            dependencies: ["AppModule"],
            path: "Tests/AppModuleTests"
        )
    ]
)
