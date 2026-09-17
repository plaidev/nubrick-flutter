// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nubrick_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "nubrick-flutter", targets: ["nubrick_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            url: "https://github.com/plaidev/nubrick-ios.git",
            exact: "0.19.15"
        )
    ],
    targets: [
        .target(
            name: "nubrick_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Nubrick", package: "nubrick-ios")
            ]
        )
    ]
)
