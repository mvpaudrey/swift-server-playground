import Vapor
import GRPC
import NIO
import Fluent
import FluentPostgresDriver

/// Configure the Vapor application
public func configure(_ app: Application) async throws {
    // MARK: - Environment Configuration

    // Get API key from environment or use provided key
    let apiKey = Environment.get("API_FOOTBALL_KEY") ?? "fd4b447a00e463ef9af6f423e44032a1"

    // Get gRPC port from environment or use default
    let grpcPort = Environment.get("GRPC_PORT").flatMap(Int.init) ?? 50051

    app.logger.info("Configuring AFCON Middleware...")
    app.logger.info("gRPC Server Port: \(grpcPort)")
    app.logger.info("Using in-memory caching")

    // MARK: - Database (PostgreSQL)

    if let databaseURL = Environment.get("DATABASE_URL"),
       let url = URL(string: databaseURL),
       var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
        // Ensure sslmode is set if not provided (Heroku-style URLs)
        var queryItems = comps.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "sslmode" }) {
            queryItems.append(URLQueryItem(name: "sslmode", value: "prefer"))
        }
        comps.queryItems = queryItems
        if let final = comps.url { try app.databases.use(.postgres(url: final), as: .psql) }
    } else {
        let hostname = Environment.get("PGHOST") ?? "127.0.0.1"
        let port = Environment.get("PGPORT").flatMap(Int.init) ?? 5432
        let username = Environment.get("PGUSER") ?? "postgres"
        let password = Environment.get("PGPASSWORD") ?? "postgres"
        let database = Environment.get("PGDATABASE") ?? "afcon"
        app.databases.use(.postgres(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tlsConfiguration: nil
        ), as: .psql)
    }

    // Migrations
    app.migrations.add(CreateLeagueEntity())
    app.migrations.add(CreateFixtureEntity())

    // Run migrations on boot
    try await app.autoMigrate()

    // MARK: - Services Registration

    // Register API Football Client
    app.services.use { app -> APIFootballClient in
        APIFootballClient(
            apiKey: apiKey,
            client: app.client,
            logger: app.logger
        )
    }

    // Register Cache Service
    app.services.use { app -> CacheService in
        CacheService(logger: app.logger)
    }

    // MARK: - HTTP Routes (Optional REST API for debugging)

    try routes(app)

    // MARK: - gRPC Server Configuration

    // Note: gRPC server will be started separately in main.swift
    // This is because Vapor and gRPC both need to run concurrently

    app.logger.info("✅ Application configured successfully")
}

/// Simple service container
final class ServiceContainer {
    private var factories: [String: (Application) -> Any] = [:]

    func register<T>(_ type: T.Type, factory: @escaping (Application) -> T) {
        let key = String(describing: type)
        factories[key] = factory
    }

    func resolve<T>(_ type: T.Type, from app: Application) -> T {
        let key = String(describing: type)
        guard let factory = factories[key] else {
            fatalError("Service \(T.self) not registered")
        }
        return factory(app) as! T
    }
}

private var serviceContainer = ServiceContainer()

extension Application.Services {
    func use<T>(_ factory: @escaping (Application) -> T) {
        serviceContainer.register(T.self, factory: factory)
    }
}

extension Application {
    public func getService<T>() -> T {
        return serviceContainer.resolve(T.self, from: self)
    }
}

extension Request {
    public func getService<T>() -> T {
        return application.getService()
    }
}
