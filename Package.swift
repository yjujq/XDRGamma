// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "XDRGamma",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "XDRGamma", path: "Sources/XDRGamma")
    ]
)
