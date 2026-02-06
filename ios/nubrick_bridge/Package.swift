// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nubrick_bridge",
    platforms: [
        .iOS("13.4")
    ],
    products: [
        .library(name: "nubrick-bridge", targets: ["nubrick_bridge"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/plaidev/nubrick-ios.git",
            exact: "0.15.3"
        )
    ],
    targets: [
        .target(
            name: "nubrick_bridge",
            dependencies: [
                .product(name: "Nubrick", package: "nubrick-ios")
            ]
        )
    ]
)
