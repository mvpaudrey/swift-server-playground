// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AFCONClientExample",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        // Use the main AFCONClient package from parent directory
        .package(path: "../..")
    ],
    targets: [
        // Executable target that uses the main AFCONClient
        .executableTarget(
            name: "AFCONClientExample",
            dependencies: [
                .product(name: "AFCONClient", package: "AFCONMiddleware")
            ],
            path: "Sources"
        )
    ]
)
