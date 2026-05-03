// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Murmur", targets: ["Murmur"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Murmur",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Murmur/Sources"
        )
    ]
)
