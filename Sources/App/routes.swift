import Vapor
import Fluent

// MARK: - Response Models

struct StandingsUpdateStatus: Content {
    let leagueId: Int
    let isActive: Bool
    let lastUpdate: Date?
}

/// Register HTTP routes for debugging and testing
public func routes(_ app: Application) throws {
    // Health check endpoint
    app.get("health") { req async throws -> [String: String] in
        return ["status": "healthy", "service": "AFCON Middleware"]
    }

    // MARK: - Debug Endpoints (REST API for testing)

    let api = app.grouped("api", "v1")

    // Get league info
    api.get("league", ":id", "season", ":season") { req async throws -> LeagueData in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        return try await cache.getOrFetchLeague(id: leagueId, season: season) {
            try await apiClient.getLeague(id: leagueId, season: season)
        }
    }

    // Get teams
    api.get("league", ":id", "season", ":season", "teams") { req async throws -> [TeamData] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        return try await cache.getOrFetchTeams(leagueID: leagueId, season: season) {
            try await apiClient.getTeams(leagueId: leagueId, season: season)
        }
    }

    // Refresh leagues from upstream and store in PostgreSQL (intended to be called weekly)
    api.post("leagues", "refresh") { req async throws -> [String: Int] in
        // Optional filters; defaults pick active/current season leagues only
        let season = try? req.query.get(Int.self, at: "season")
        let current: Bool = (try? req.query.get(Bool.self, at: "current")) ?? true
        let country = try? req.query.get(String.self, at: "country")
        let type = try? req.query.get(String.self, at: "type") // e.g., "League" or "Cup"

        let apiClient: APIFootballClient = req.getService()

        // Fetch leagues (filtering to reduce volume)
        let leagues = try await apiClient.listLeagues(
            name: nil,
            current: current,
            season: season,
            country: country,
            type: type
        )

        var inserted = 0
        var updated = 0

        for item in leagues {
            let apiId = item.league.id
            let existing = try await LeagueEntity.query(on: req.db)
                .filter(\.$apiLeagueId == apiId)
                .first()

            let currentSeason = item.seasons.first(where: { $0.current })?.year
            if let league = existing {
                league.name = item.league.name
                league.type = item.league.type
                league.countryName = item.country.name
                league.countryCode = item.country.code
                league.logo = item.league.logo
                league.currentSeason = currentSeason
                league.active = true
                try await league.save(on: req.db)
                updated += 1
            } else {
                let league = LeagueEntity(
                    apiLeagueId: apiId,
                    name: item.league.name,
                    type: item.league.type,
                    countryName: item.country.name,
                    countryCode: item.country.code,
                    logo: item.league.logo,
                    currentSeason: currentSeason,
                    active: true
                )
                try await league.create(on: req.db)
                inserted += 1
            }
        }

        return ["inserted": inserted, "updated": updated]
    }

    // Search leagues from PostgreSQL
    api.get("leagues") { req async throws -> [LeagueEntity] in
        let rawQ: String? = try? req.query.get(String.self, at: "query")
        let q = rawQ?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = min((try? req.query.get(Int.self, at: "limit")) ?? 25, 100)
        let country = try? req.query.get(String.self, at: "country")
        var builder = LeagueEntity.query(on: req.db).filter(\.$active == true)
        if let country, !country.isEmpty {
            // Case-insensitive match on country name
            builder = builder.filter(\.$countryName, .custom("ILIKE"), country)
        }
        if let q, !q.isEmpty {
            // Case-insensitive starts-with search on league name
            let pattern = "\(q)%"
            builder = builder.filter(\.$name, .custom("ILIKE"), pattern)
        }
        return try await builder.sort(\.$name, .ascending).limit(limit).all()
    }

    // Get fixtures
    api.get("league", ":id", "season", ":season", "fixtures") { req async throws -> [FixtureData] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let date = req.query[String.self, at: "date"]
        let teamId = req.query[Int.self, at: "team"]
        let live = req.query[Bool.self, at: "live"] ?? false

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        return try await cache.getOrFetchFixtures(
            leagueID: leagueId,
            season: season,
            date: date,
            teamID: teamId,
            live: live
        ) {
            try await apiClient.getFixtures(
                leagueId: leagueId,
                season: season,
                date: date,
                teamId: teamId,
                live: live
            )
        }
    }

    // Get live fixtures
    api.get("league", ":id", "live") { req async throws -> [FixtureData] in
        guard let leagueId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()
        return try await cache.getOrFetchLiveFixtures(leagueID: leagueId) {
            try await apiClient.getLiveFixtures(leagueId: leagueId)
        }
    }

    // Get fixture by ID
    api.get("fixture", ":id") { req async throws -> FixtureData in
        guard let fixtureId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid fixture ID")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()
        return try await cache.getOrFetchFixtureById(fixtureID: fixtureId) {
            try await apiClient.getFixtureById(fixtureId: fixtureId)
        }
    }

    // Get fixture by ID with events
    api.get("fixture", ":id", "events") { req async throws -> [FixtureEvent] in
        guard let fixtureId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid fixture ID")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()
        return try await cache.getOrFetchFixtureEvents(fixtureID: fixtureId) {
            try await apiClient.getFixtureEvents(fixtureId: fixtureId)
        }
    }

    // Get fixture lineups
    api.get("fixture", ":id", "lineups") { req async throws -> [FixtureLineup] in
        guard let fixtureId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid fixture ID")
        }

        let apiClient: APIFootballClient = req.getService()
        return try await apiClient.getFixtureLineups(fixtureId: fixtureId)
    }

    // Get fixture statistics
    api.get("fixture", ":id", "statistics") { req async throws -> [FixtureStatistics] in
        guard let fixtureId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid fixture ID")
        }

        let apiClient: APIFootballClient = req.getService()
        return try await apiClient.getFixtureStatistics(fixtureId: fixtureId)
    }

    // Get head to head between two teams
    api.get("h2h", ":team1", ":team2") { req async throws -> [HeadToHeadData] in
        guard let team1 = req.parameters.get("team1", as: Int.self),
              let team2 = req.parameters.get("team2", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid team IDs")
        }

        let last = req.query[Int.self, at: "last"]

        let apiClient: APIFootballClient = req.getService()
        return try await apiClient.getHeadToHead(team1: team1, team2: team2, last: last)
    }

    // Get fixtures by date (across all leagues or specific league)
    api.get("fixtures", "date", ":date") { req async throws -> [FixtureData] in
        guard let date = req.parameters.get("date", as: String.self) else {
            throw Abort(.badRequest, reason: "Invalid date format. Use YYYY-MM-DD")
        }

        // Optional: filter by league
        let leagueId = req.query[Int.self, at: "league"]
        let season = req.query[Int.self, at: "season"]

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        if let leagueId = leagueId, let season = season {
            // Get fixtures for specific league and date
            return try await cache.getOrFetchFixtures(
                leagueID: leagueId,
                season: season,
                date: date,
                teamID: nil,
                live: false
            ) {
                try await apiClient.getFixtures(
                    leagueId: leagueId,
                    season: season,
                    date: date,
                    teamId: nil,
                    live: false
                )
            }
        } else {
            // Get all fixtures for the date (any league)
            return try await apiClient.getFixtures(
                leagueId: 0,
                season: 0,
                date: date,
                teamId: nil,
                live: false
            )
        }
    }

    // Get today's upcoming fixtures
    api.get("league", ":id", "season", ":season", "today") { req async throws -> [FixtureData] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        // Get today's date in YYYY-MM-DD format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        // Fetch today's fixtures
        let allFixtures = try await cache.getOrFetchFixtures(
            leagueID: leagueId,
            season: season,
            date: today,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: leagueId,
                season: season,
                date: today,
                teamId: nil,
                live: false
            )
        }

        // Filter for upcoming games only (not started, not finished)
        let upcomingFixtures = allFixtures.filter { fixture in
            let status = fixture.fixture.status.short
            // Include: NS (Not Started), TBD (To Be Defined), etc.
            // Exclude: FT (Full Time), AET (After Extra Time), PEN (Penalties),
            //          CANC (Cancelled), PST (Postponed), ABD (Abandoned),
            //          1H, HT, 2H, ET, BT, P, SUSP, INT, LIVE (ongoing matches)
            return status == "NS" || status == "TBD"
        }

        return upcomingFixtures
    }

    // Get standings
    api.get("league", ":id", "season", ":season", "standings") { req async throws -> [StandingsData] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let apiClient: APIFootballClient = req.getService()
        let cache: CacheService = req.getService()

        return try await cache.getOrFetchStandings(leagueID: leagueId, season: season) {
            try await apiClient.getStandings(leagueId: leagueId, season: season)
        }
    }

    // Start automatic standings updates for a league
    api.post("league", ":id", "season", ":season", "standings", "start") { req async throws -> [String: String] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let standingsService: StandingsUpdateService = req.getService()
        standingsService.startUpdates(leagueID: leagueId, season: season)

        return [
            "status": "started",
            "leagueId": "\(leagueId)",
            "season": "\(season)",
            "message": "Standings updates started. Will poll every hour during games, then at 10, 20, 30 min and 1h 5min after last game."
        ]
    }

    // Stop automatic standings updates for a league
    api.post("league", ":id", "standings", "stop") { req async throws -> [String: String] in
        guard let leagueId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID")
        }

        let standingsService: StandingsUpdateService = req.getService()
        standingsService.stopUpdates(leagueID: leagueId)

        return [
            "status": "stopped",
            "leagueId": "\(leagueId)",
            "message": "Standings updates stopped"
        ]
    }

    // Get standings update status
    api.get("league", ":id", "standings", "status") { req async throws -> StandingsUpdateStatus in
        guard let leagueId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID")
        }

        let standingsService: StandingsUpdateService = req.getService()
        let isActive = standingsService.isActive(leagueID: leagueId)
        let lastUpdate = standingsService.getLastUpdateTime(leagueID: leagueId)

        return StandingsUpdateStatus(
            leagueId: leagueId,
            isActive: isActive,
            lastUpdate: lastUpdate
        )
    }

    // Manually trigger standings update
    api.post("league", ":id", "season", ":season", "standings", "update") { req async throws -> [String: String] in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let standingsService: StandingsUpdateService = req.getService()
        try await standingsService.updateStandingsNow(leagueID: leagueId, season: season)

        return [
            "status": "updated",
            "leagueId": "\(leagueId)",
            "season": "\(season)",
            "message": "Standings updated successfully"
        ]
    }

    // Get team details
    api.get("team", ":id") { req async throws -> TeamData in
        guard let teamId = req.parameters.get("id", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid team ID")
        }

        let apiClient: APIFootballClient = req.getService()
        return try await apiClient.getTeamDetails(teamId: teamId)
    }

    // Clear cache
    api.delete("cache", "league", ":id", "season", ":season") { req async throws -> HTTPStatus in
        guard let leagueId = req.parameters.get("id", as: Int.self),
              let season = req.parameters.get("season", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid league ID or season")
        }

        let cache: CacheService = req.getService()
        try await cache.invalidateLeagueSeason(leagueID: leagueId, season: season)

        return .noContent
    }

    app.logger.info("✅ HTTP routes configured")
}
