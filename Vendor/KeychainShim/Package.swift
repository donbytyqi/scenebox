// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeychainShim",
    platforms: [.iOS(.v17), .tvOS(.v17), .macCatalyst(.v17)],
    products: [
        .library(name: "KeychainShim", type: .dynamic, targets: ["KeychainShim"]),
    ],
    targets: [
        .target(name: "KeychainShim", linkerSettings: [.linkedFramework("Security")]),
    ]
)
