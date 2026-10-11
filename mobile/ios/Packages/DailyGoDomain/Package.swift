// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyGoDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DailyGoDomain", targets: ["DailyGoDomain"])],
    targets: [
        .target(name: "DailyGoDomain"),
        .testTarget(name: "DailyGoDomainTests", dependencies: ["DailyGoDomain"])
    ]
)