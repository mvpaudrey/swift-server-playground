import Foundation
import Vapor

/// Simplified cache service using in-memory caching
/// For production, integrate with Redis or another caching solution
public final class CacheService {
    private var cache: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let logger: Logger

    struct CacheEntry {
        let data: Data
        let expiry: Date
    }

    // Cache TTL (Time To Live) values in seconds
    enum CacheTTL {
        static let league: Int = 86400        // 24 hours
        static let teams: Int = 43200         // 12 hours
        static let fixtures: Int = 1800       // 30 minutes
        static let liveMatch: Int = 60        // 60 seconds (live refresh)
        static let standingsLive: Int = 3600  // 1 hour (when matches are in progress)
        static let standingsIdle: Int = 86400 // 24 hours (when no matches are in progress)
        static let players: Int = 43200       // 12 hours
        static let fixtureById: Int = 60      // 60 seconds
        static let events: Int = 60           // 60 seconds
    }

    public init(logger: Logger) {
        self.logger = logger
    }

    // MARK: - Generic Cache Methods

    func get<T: Codable>(key: String) async throws -> T? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else {
            logger.debug("Cache miss for key: \(key)")
            return nil
        }

        // Check if expired
        if entry.expiry < Date() {
            cache.removeValue(forKey: key)
            logger.debug("Cache expired for key: \(key)")
            return nil
        }

        let value = try JSONDecoder().decode(T.self, from: entry.data)
        logger.debug("Cache hit for key: \(key)")
        return value
    }

    func set<T: Codable>(key: String, value: T, ttl: Int) async throws {
        let data = try JSONEncoder().encode(value)
        let expiry = Date().addingTimeInterval(TimeInterval(ttl))

        lock.lock()
        cache[key] = CacheEntry(data: data, expiry: expiry)
        lock.unlock()

        logger.debug("Cached value for key: \(key) with TTL: \(ttl)s")
    }

    func delete(key: String) async throws {
        lock.lock()
        cache.removeValue(forKey: key)
        lock.unlock()

        logger.debug("Deleted cache for key: \(key)")
    }

    func clearPattern(pattern: String) async throws {
        lock.lock()
        let keysToRemove = cache.keys.filter { $0.contains(pattern.replacingOccurrences(of: "*", with: "")) }
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
        lock.unlock()

        logger.info("Cleared \(keysToRemove.count) cache entries matching pattern: \(pattern)")
    }

    // MARK: - Cache Key Generators

    func leagueKey(id: Int, season: Int) -> String {
        return "afcon:league:\(id):season:\(season)"
    }

    func teamsKey(leagueID: Int, season: Int) -> String {
        return "afcon:teams:league:\(leagueID):season:\(season)"
    }

    func fixturesKey(leagueID: Int, season: Int, date: String? = nil, teamID: Int? = nil) -> String {
        var key = "afcon:fixtures:league:\(leagueID):season:\(season)"
        if let date = date {
            key += ":date:\(date)"
        }
        if let teamID = teamID {
            key += ":team:\(teamID)"
        }
        return key
    }

    func standingsKey(leagueID: Int, season: Int) -> String {
        return "afcon:standings:league:\(leagueID):season:\(season)"
    }

    func fixtureIdKey(id: Int) -> String {
        return "afcon:fixture:id:\(id)"
    }

    func fixtureEventsKey(id: Int) -> String {
        return "afcon:fixture:id:\(id):events"
    }

    // MARK: - High-Level Cache Methods

    func getOrFetchLeague(
        id: Int,
        season: Int,
        fetcher: () async throws -> LeagueData
    ) async throws -> LeagueData {
        let key = leagueKey(id: id, season: season)

        if let cached: LeagueData = try await get(key: key) {
            return cached
        }

        let fresh = try await fetcher()
        try await set(key: key, value: fresh, ttl: CacheTTL.league)
        return fresh
    }

    func getOrFetchTeams(
        leagueID: Int,
        season: Int,
        fetcher: () async throws -> [TeamData]
    ) async throws -> [TeamData] {
        let key = teamsKey(leagueID: leagueID, season: season)

        if let cached: [TeamData] = try await get(key: key) {
            return cached
        }

        let fresh = try await fetcher()
        try await set(key: key, value: fresh, ttl: CacheTTL.teams)
        return fresh
    }

    func getOrFetchFixtures(
        leagueID: Int,
        season: Int,
        date: String? = nil,
        teamID: Int? = nil,
        live: Bool = false,
        fetcher: () async throws -> [FixtureData]
    ) async throws -> [FixtureData] {
        let key = fixturesKey(leagueID: leagueID, season: season, date: date, teamID: teamID)

        if let cached: [FixtureData] = try await get(key: key) {
            return cached
        }

        let fresh = try await fetcher()
        let ttl = live ? CacheTTL.liveMatch : CacheTTL.fixtures
        try await set(key: key, value: fresh, ttl: ttl)
        return fresh
    }

    func getOrFetchStandings(
        leagueID: Int,
        season: Int,
        hasLiveMatches: Bool = false,
        fetcher: () async throws -> [StandingsData]
    ) async throws -> [StandingsData] {
        let key = standingsKey(leagueID: leagueID, season: season)

        if let cached: [StandingsData] = try await get(key: key) {
            logger.info("📊 Standings cache hit for league \(leagueID)")
            return cached
        }

        let fresh = try await fetcher()

        // Use different TTL based on whether matches are in progress
        let ttl = hasLiveMatches ? CacheTTL.standingsLive : CacheTTL.standingsIdle
        let ttlHours = ttl / 3600

        logger.info("📊 Caching standings for league \(leagueID) with TTL: \(ttlHours)h (\(hasLiveMatches ? "live matches" : "no live matches"))")
        try await set(key: key, value: fresh, ttl: ttl)
        return fresh
    }

    func getOrFetchFixtureById(
        fixtureID: Int,
        fetcher: () async throws -> FixtureData
    ) async throws -> FixtureData {
        let key = fixtureIdKey(id: fixtureID)

        if let cached: FixtureData = try await get(key: key) {
            return cached
        }

        let fresh = try await fetcher()
        try await set(key: key, value: fresh, ttl: CacheTTL.fixtureById)
        return fresh
    }

    func getOrFetchFixtureEvents(
        fixtureID: Int,
        fetcher: () async throws -> [FixtureEvent]
    ) async throws -> [FixtureEvent] {
        let key = fixtureEventsKey(id: fixtureID)

        if let cached: [FixtureEvent] = try await get(key: key) {
            return cached
        }

        let fresh = try await fetcher()
        try await set(key: key, value: fresh, ttl: CacheTTL.events)
        return fresh
    }

    func invalidateLeagueSeason(leagueID: Int, season: Int) async throws {
        let pattern = "afcon:*:league:\(leagueID):season:\(season)"
        try await clearPattern(pattern: pattern)
    }
}
