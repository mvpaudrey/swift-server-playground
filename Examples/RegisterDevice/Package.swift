// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RegisterDevice",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../../")
    ],
    targets: [
        .executableTarget(
            name: "RegisterDevice",
            dependencies: [
                .product(name: "AFCONClient", package: "swift-server-playground")
            ]
        )
    ]
)
