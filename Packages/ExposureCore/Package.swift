// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExposureCore",
    products: [.library(name: "ExposureCore", targets: ["ExposureCore"])],
    targets: [
        .target(name: "ExposureCore"),
        .testTarget(name: "ExposureCoreTests", dependencies: ["ExposureCore"])
    ]
)
