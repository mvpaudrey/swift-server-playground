// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "AFCONMiddleware",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
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

        // gRPC Swift 2.x (Swift 6.0+ compatible)
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "1.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "1.0.0"),

        // SwiftProtobuf for protocol buffers (Swift 6.0+ compatible)
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),

        // APNSwift for Apple Push Notifications
        .package(url: "https://github.com/swift-server-community/APNSwift.git", from: "5.0.0"),
    ],
    targets: [
        // Client library for iOS/macOS apps (no Vapor dependency)
        .target(
            name: "AFCONClient",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "Sources/AFCONClient",
            exclude: [
                "AFCONDataManager.swift.bak",
                "AFCONDataManager.swift.v2",
                "Protos/afcon.proto",
                "Resources/export-fallback-data.sh",
                "Resources/README.md",
                "SWIFTDATA_CACHING_GUIDE.md",
                "TROUBLESHOOTING.md",
                "grpc-swift-proto-generator-config.json",
                "Examples",
            ],
            resources: [
                .process("Resources/league_fallback.json"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Server application
        .target(
            name: "App",
            dependencies: [
                // .target(name: "AFCONClient"),  // Temporarily disabled - has grpc-swift 1.x generated code
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "GRPCCore", package: "grpc-swift"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "APNS", package: "APNSwift"),
            ],
            exclude: [
                "Protos/afcon.proto",
                "grpc-swift-proto-generator-config.json",
                "gRPC/Generated/README.md",
                "gRPC/Server/AFCONServiceProvider.swift.grpc1x.backup",
            ],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release))
            ]
        ),
        .executableTarget(
            name: "Run",
            dependencies: [.target(name: "App")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
