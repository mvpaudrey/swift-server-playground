import Foundation
import Vapor
import Fluent

/// Repository for managing fixtures in the database
public final class FixtureRepository: @unchecked Sendable {
    private let db: any Database
    private let logger: Logger

    public init(db: any Database, logger: Logger) {
        self.db = db
        self.logger = logger
    }

    // MARK: - Create/Update Operations

    /// Upsert (insert or update) a fixture
    func upsert(from fixtureData: FixtureData, leagueId: Int, season: Int, competition: String) async throws {
        let fixture = try await FixtureEntity.query(on: db)
            .filter(\.$apiFixtureId == fixtureData.fixture.id)
            .first()

        if let existing = fixture {
            // Update existing
            existing.statusLong = fixtureData.fixture.status.long
            existing.statusShort = fixtureData.fixture.status.short
            existing.statusElapsed = fixtureData.fixture.status.elapsed
            existing.homeGoals = fixtureData.goals.home
            existing.awayGoals = fixtureData.goals.away
            existing.halftimeHome = fixtureData.score.halftime.home
            existing.halftimeAway = fixtureData.score.halftime.away
            existing.fulltimeHome = fixtureData.score.fulltime.home
            existing.fulltimeAway = fixtureData.score.fulltime.away
            existing.homeTeamWinner = fixtureData.teams.home.winner
            existing.awayTeamWinner = fixtureData.teams.away.winner
            try await existing.save(on: db)
        } else {
            // Insert new
            let newFixture = FixtureEntity(
                apiFixtureId: fixtureData.fixture.id,
                leagueId: leagueId,
                season: season,
                referee: fixtureData.fixture.referee,
                timezone: fixtureData.fixture.timezone,
                date: Date(timeIntervalSince1970: TimeInterval(fixtureData.fixture.timestamp)),
                timestamp: fixtureData.fixture.timestamp,
                venueId: fixtureData.fixture.venue.id ?? 0,
                venueName: fixtureData.fixture.venue.name ?? "",
                venueCity: fixtureData.fixture.venue.city,
                statusLong: fixtureData.fixture.status.long,
                statusShort: fixtureData.fixture.status.short,
                statusElapsed: fixtureData.fixture.status.elapsed,
                homeTeamId: fixtureData.teams.home.id,
                homeTeamName: fixtureData.teams.home.name,
                homeTeamLogo: fixtureData.teams.home.logo,
                homeTeamWinner: fixtureData.teams.home.winner,
                awayTeamId: fixtureData.teams.away.id,
                awayTeamName: fixtureData.teams.away.name,
                awayTeamLogo: fixtureData.teams.away.logo,
                awayTeamWinner: fixtureData.teams.away.winner,
                homeGoals: fixtureData.goals.home,
                awayGoals: fixtureData.goals.away,
                halftimeHome: fixtureData.score.halftime.home,
                halftimeAway: fixtureData.score.halftime.away,
                fulltimeHome: fixtureData.score.fulltime.home,
                fulltimeAway: fixtureData.score.fulltime.away,
                periodFirst: fixtureData.fixture.periods.first,
                periodSecond: fixtureData.fixture.periods.second,
                competition: competition
            )
            try await newFixture.save(on: db)
        }
    }

    /// Batch upsert fixtures
    func upsertBatch(fixtures: [FixtureData], leagueId: Int, season: Int, competition: String) async throws {
        for fixture in fixtures {
            try await upsert(from: fixture, leagueId: leagueId, season: season, competition: competition)
        }
        logger.info("Upserted \(fixtures.count) fixtures for league \(leagueId), season \(season)")
    }

    // MARK: - Query Operations

    /// Get next upcoming fixture timestamp for a league
    func getNextUpcomingTimestamp(leagueId: Int, season: Int) async throws -> Int? {
        let now = Date()

        let fixture = try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$date > now)
            .group(.or) { group in
                group.filter(\.$statusShort == "NS")
                group.filter(\.$statusShort == "TBD")
            }
            .sort(\.$timestamp, .ascending)
            .first()

        return fixture?.timestamp
    }

    /// Get all fixtures at a specific timestamp (games happening at the same time)
    func getFixturesAtTimestamp(leagueId: Int, season: Int, timestamp: Int) async throws -> [FixtureEntity] {
        return try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$timestamp == timestamp)
            .all()
    }

    /// Get all upcoming fixtures for a league
    func getUpcomingFixtures(leagueId: Int, season: Int) async throws -> [FixtureEntity] {
        let now = Date()

        return try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$date > now)
            .group(.or) { group in
                group.filter(\.$statusShort == "NS")
                group.filter(\.$statusShort == "TBD")
            }
            .sort(\.$timestamp, .ascending)
            .all()
    }

    /// Get the earliest and latest fixture start times for the day containing the provided date
    func getDailyFixtureWindow(
        leagueId: Int,
        season: Int,
        containing referenceDate: Date
    ) async throws -> (earliest: Date, latest: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        guard let gmt = TimeZone(secondsFromGMT: 0) else {
            return nil
        }
        calendar.timeZone = gmt
        let startOfDay = calendar.startOfDay(for: referenceDate)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return nil
        }

        let fixtures = try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$date >= startOfDay)
            .filter(\.$date < nextDay)
            .sort(\.$date, .ascending)
            .all()

        guard let first = fixtures.first, let last = fixtures.last else {
            return nil
        }

        return (earliest: first.date, latest: last.date)
    }

    /// Fetch all fixtures for the specified league/season on the provided calendar day (UTC)
    func getFixturesForDate(
        leagueId: Int,
        season: Int,
        date: Date
    ) async throws -> [FixtureEntity] {
        var calendar = Calendar(identifier: .gregorian)
        guard let gmt = TimeZone(secondsFromGMT: 0) else {
            return []
        }
        calendar.timeZone = gmt
        let startOfDay = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$date >= startOfDay)
            .filter(\.$date < nextDay)
            .sort(\.$date, .ascending)
            .all()
    }

    /// Get all fixtures for a league/season (for initial sync)
    func getAllFixtures(leagueId: Int, season: Int) async throws -> [FixtureEntity] {
        return try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .sort(\.$timestamp, .ascending)
            .all()
    }

    /// Get fixture by API ID
    func getFixture(byApiId apiId: Int) async throws -> FixtureEntity? {
        return try await FixtureEntity.query(on: db)
            .filter(\.$apiFixtureId == apiId)
            .first()
    }

    /// Check if fixtures exist for a league/season
    func hasFixtures(leagueId: Int, season: Int) async throws -> Bool {
        let count = try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .count()
        return count > 0
    }

    /// Delete old finished fixtures (cleanup)
    func deleteFinishedFixtures(olderThan date: Date) async throws {
        try await FixtureEntity.query(on: db)
            .filter(\.$date < date)
            .group(.or) { group in
                group.filter(\.$statusShort == "FT")
                group.filter(\.$statusShort == "AET")
                group.filter(\.$statusShort == "PEN")
            }
            .delete()
    }

    /// Check if there are any live matches for a given league
    /// Returns true if at least one match is in progress
    func hasLiveMatches(leagueId: Int, season: Int) async throws -> Bool {
        // First, get ALL fixtures for this league/season to see their statuses
        let allFixtures = try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .all()

        let statusCounts = Dictionary(grouping: allFixtures) { $0.statusShort }
            .mapValues { $0.count }

        logger.info("📊 All fixture statuses for league \(leagueId): \(statusCounts)")

        // Now check for live matches
        let liveFixtures = try await FixtureEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .group(.or) { group in
                // Live status codes: 1H, HT, 2H, ET, BT, P, LIVE
                group.filter(\.$statusShort == "1H")  // First Half
                group.filter(\.$statusShort == "HT")  // Halftime
                group.filter(\.$statusShort == "2H")  // Second Half
                group.filter(\.$statusShort == "ET")  // Extra Time
                group.filter(\.$statusShort == "BT")  // Break Time
                group.filter(\.$statusShort == "P")   // Penalties
                group.filter(\.$statusShort == "LIVE") // Live (generic)
                group.filter(\.$statusShort == "SUSP") // Suspended
                group.filter(\.$statusShort == "INT")  // Interrupted
            }
            .all()

        if !liveFixtures.isEmpty {
            logger.info("🔴 Live matches found: \(liveFixtures.count)")
            for fixture in liveFixtures {
                logger.info("  - Fixture \(fixture.apiFixtureId): \(fixture.homeTeamName) vs \(fixture.awayTeamName) (\(fixture.statusShort) - \(fixture.statusLong))")
            }
        } else {
            logger.info("📊 Live match check for league \(leagueId): 0 matches in progress")
        }

        return !liveFixtures.isEmpty
    }
}
