// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "nubrick_flutter",
    platforms: [
        .iOS("13.4")
    ],
    products: [
        .library(name: "nubrick-flutter", targets: ["nubrick_flutter"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/plaidev/nubrick-ios.git",
            exact: "0.16.1"
        )
    ],
    targets: [
        .target(
            name: "nubrick_flutter",
            dependencies: [
                .product(name: "Nubrick", package: "nubrick-ios")
            ]
        )
    ]
)
