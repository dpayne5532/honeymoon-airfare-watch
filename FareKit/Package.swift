// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FareKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "FareKit", targets: ["FareKit"]),
    ],
    targets: [
        .target(name: "FareKit"),
        .testTarget(name: "FareKitTests", dependencies: ["FareKit"]),
    ]
)
