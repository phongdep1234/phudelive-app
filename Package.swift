// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PhuDeLive",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "PhuDeLive",
            path: "Sources/PhuDeLive",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Translation"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
