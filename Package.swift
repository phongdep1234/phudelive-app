// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PhuDeLive",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PhuDeLive",
            path: "Sources/PhuDeLive",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Translation"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
