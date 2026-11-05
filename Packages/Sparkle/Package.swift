// swift-tools-version:5.5
// Sparkle's own binary target (its Package.swift at this tag), without cloning its repository,
// which takes far longer than the download.
import PackageDescription

let version = "2.10.1"

let package = Package(
    name: "Sparkle",
    platforms: [.macOS(.v12)],
    products: [.library(name: "Sparkle", targets: ["Sparkle"])],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/\(version)/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
    ]
)
