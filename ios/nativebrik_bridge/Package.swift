// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nativebrik_bridge",
    platforms: [
        .iOS("13.4")
    ],
    products: [
        .library(name: "nativebrik-bridge", targets: ["nativebrik_bridge"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/plaidev/nubrick-ios.git",
            exact: "0.15.2"
        )
    ],
    targets: [
        .target(
            name: "nativebrik_bridge",
            dependencies: [
                .product(name: "Nubrick", package: "nubrick-ios")
            ]
        )
    ]
)
