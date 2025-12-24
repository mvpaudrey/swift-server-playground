import Vapor
import GRPCCore
import GRPCNIOTransportHTTP2
import Fluent
import App

/// Main entry point for the AFCON Middleware application
/// Runs both HTTP (Vapor) and gRPC servers concurrently

@main
struct Main {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)

        // Configure Vapor application
        try await App.configure(app)

        // Get gRPC port from environment
        let grpcPort = Environment.get("GRPC_PORT").flatMap(Int.init) ?? 50051
        let httpPort = Environment.get("PORT").flatMap(Int.init) ?? 8080

        app.logger.info("🚀 Starting AFCON Middleware")
        app.logger.info("📡 HTTP Server will run on port \(httpPort)")
        app.logger.info("📡 gRPC Server will run on port \(grpcPort)")

        app.http.server.configuration.port = httpPort

        // Run both servers concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Start Vapor HTTP server
            group.addTask {
                try await app.execute()
            }

            // Start gRPC server
            group.addTask {
                try await startGRPCServer(port: grpcPort, app: app)
            }

            // Wait for any task to complete or throw
            try await group.next()

            // Cancel remaining tasks
            group.cancelAll()

            app.logger.info("✅ Servers shut down")
        }

        try await app.asyncShutdown()
    }

    /// Start the gRPC server using grpc-swift 2.x
    static func startGRPCServer(
        port: Int,
        app: Application
    ) async throws {
        // Get services from Vapor app
        let apiClient: APIFootballClient = app.getService()
        let cache: CacheService = app.getService()
        let notificationService: NotificationService = app.getService()
        let deviceRepository: DeviceRepository = app.getService()
        let broadcaster: LiveMatchBroadcaster = app.getService()

        // Start notification service cleanup task
        await notificationService.startCleanupTask()

        // Create FixtureRepository with database connection
        let db: any Database = app.db
        let fixtureRepository = FixtureRepository(db: db, logger: app.logger)

        // Create gRPC service provider with broadcaster for scalable live streaming
        let serviceProvider = AFCONServiceProvider(
            apiClient: apiClient,
            cache: cache,
            fixtureRepository: fixtureRepository,
            notificationService: notificationService,
            deviceRepository: deviceRepository,
            broadcaster: broadcaster,
            logger: app.logger
        )

        // Initialize fixtures database (fetch from API if empty)
        // Configure leagues via environment variables:
        // - INIT_LEAGUES: Comma-separated league definitions (format: "id:season:name,id:season:name")
        // - AUTO_INIT: Set to "false" to disable auto-initialization
        // Examples:
        //   INIT_LEAGUES="6:2025:AFCON 2025,39:2024:Premier League"
        //   AUTO_INIT=false
        let leagues = parseInitLeaguesFromEnvironment(logger: app.logger)
        await serviceProvider.initializeFixtures(leagues: leagues)

        // Configure gRPC server with grpc-swift 2.x API
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .ipv4(host: "0.0.0.0", port: port),
                transportSecurity: .plaintext
            ),
            services: [serviceProvider]
        )

        app.logger.info("gRPC server starting on 0.0.0.0:\(port)")

        // Run the server (this blocks until shutdown)
        try await server.serve()

        app.logger.info("gRPC server shut down gracefully")
    }

    /// Parse initialization leagues from environment variables
    /// Returns empty array if AUTO_INIT=false, otherwise returns configured or default leagues
    static func parseInitLeaguesFromEnvironment(logger: Logger) -> [(id: Int, season: Int, name: String)] {
        // Check if auto-initialization is disabled
        if let autoInit = Environment.get("AUTO_INIT"), autoInit.lowercased() == "false" {
            logger.info("ℹ️  Auto-initialization disabled via AUTO_INIT=false")
            return []
        }

        // Try to parse custom leagues from INIT_LEAGUES environment variable
        if let initLeaguesStr = Environment.get("INIT_LEAGUES"), !initLeaguesStr.isEmpty {
            logger.info("ℹ️  Parsing leagues from INIT_LEAGUES environment variable")

            let leagueDefinitions = initLeaguesStr.split(separator: ",").map(String.init)
            var leagues: [(id: Int, season: Int, name: String)] = []

            for definition in leagueDefinitions {
                let parts = definition.split(separator: ":").map(String.init)

                guard parts.count == 3,
                      let id = Int(parts[0]),
                      let season = Int(parts[1]) else {
                    logger.warning("⚠️  Invalid league definition: '\(definition)'. Expected format: 'id:season:name'")
                    continue
                }

                let name = parts[2]
                leagues.append((id: id, season: season, name: name))
                logger.info("✅ Configured league: \(name) (ID: \(id), Season: \(season))")
            }

            if leagues.isEmpty {
                logger.warning("⚠️  No valid leagues parsed from INIT_LEAGUES, falling back to defaults")
                return defaultLeagues()
            }

            return leagues
        }

        // Return default leagues
        logger.info("ℹ️  Using default leagues (set INIT_LEAGUES to customize)")
        return defaultLeagues()
    }

    /// Default leagues for initialization
    static func defaultLeagues() -> [(id: Int, season: Int, name: String)] {
        return [
            (6, 2025, "AFCON 2025")
        ]
    }
}

// MARK: - Service Provider Implementation Placeholder
// After running ./generate-protos.sh, implement the generated protocol here:
/*
final class AFCONServiceProviderImpl: Afcon_AFCONServiceProvider {
    private let provider: AFCONServiceProvider
    private let streamProvider: LiveMatchStreamProvider

    init(_ provider: AFCONServiceProvider, _ streamProvider: LiveMatchStreamProvider) {
        self.provider = provider
        self.streamProvider = streamProvider
    }

    func getLeague(
        request: Afcon_LeagueRequest,
        context: StatusOnlyCallContext
    ) -> EventLoopFuture<Afcon_LeagueResponse> {
        // Implementation using provider.convertLeagueResponse()
    }

    func getTeams(
        request: Afcon_TeamsRequest,
        context: StatusOnlyCallContext
    ) -> EventLoopFuture<Afcon_TeamsResponse> {
        // Implementation using provider.convertTeamInfo()
    }

    func streamLiveMatches(
        request: Afcon_LiveMatchRequest,
        context: StreamingResponseCallContext<Afcon_LiveMatchUpdate>
    ) -> EventLoopFuture<GRPCStatus> {
        // Implementation using streamProvider.streamLiveMatches()
    }

    // ... implement other RPC methods
}
*/
