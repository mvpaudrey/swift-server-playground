// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AFCONMiddleware",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "AFCONClient", targets: ["AFCONClient"]),
    ],
    dependencies: [
        // Vapor framework
        .package(url: "https://github.com/vapor/vapor.git", from: "4.89.0"),
        // Fluent ORM + Postgres driver
        .package(url: "https://github.com/vapor/fluent.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),

        // gRPC Swift
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.21.0"),

        // SwiftProtobuf for protocol buffers
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
    ],
    targets: [
        // Client library for iOS/macOS apps (no Vapor dependency)
        .target(
            name: "AFCONClient",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/AFCONClient"
        ),

        // Server application
        .target(
            name: "App",
            dependencies: [
                .target(name: "AFCONClient"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: [
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")]),
        .executableTarget(
            name: "GRPCClient",
            dependencies: [
                .target(name: "AFCONClient"),
                .product(name: "GRPC", package: "grpc-swift"),
            ],
            path: "Tests/GRPCClient"
        ),
        .testTarget(name: "AppTests", dependencies: [
            .target(name: "App"),
            .product(name: "XCTVapor", package: "vapor"),
        ])
    ]
)
