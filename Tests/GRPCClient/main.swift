import Foundation
import GRPC
import NIO
import Logging
import AFCONClient

/// Simple gRPC client for testing AFCON Middleware
@main
struct GRPCTestClient {
    static func main() async throws {
        // Setup logger
        var logger = Logger(label: "grpc.test.client")
        logger.logLevel = .info

        logger.info("🧪 AFCON Middleware gRPC Test Client")
        logger.info("=====================================")

        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try? group.syncShutdownGracefully()
        }

        // Connect to gRPC server
        let channel = try GRPCChannelPool.with(
            target: .host("localhost", port: 50051),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        defer {
            try? channel.close().wait()
        }

        // Create client
        let client = Afcon_AFCONServiceAsyncClient(channel: channel)

        logger.info("📡 Connected to gRPC server at localhost:50051")

        // Test 1: GetLeague
        logger.info("Test 1: GetLeague (AFCON 2025)")
        logger.info("--------------------------------")
        do {
            var leagueRequest = Afcon_LeagueRequest()
            leagueRequest.leagueID = 6
            leagueRequest.season = 2025

            let leagueResponse = try await client.getLeague(leagueRequest)
            logger.info("✅ League: \(leagueResponse.league.name)")
            logger.info("   Country: \(leagueResponse.country.name)")
            logger.info("   Type: \(leagueResponse.league.type)")
            logger.info("   Seasons: \(leagueResponse.seasons.count)")
            if let currentSeason = leagueResponse.seasons.first(where: { $0.current }) {
                logger.info("   Current Season: \(currentSeason.year)")
            }
        } catch {
            logger.error("❌ Error: \(error)")
        }

        // Test 2: GetTeams
        logger.info("Test 2: GetTeams (AFCON 2025)")
        logger.info("--------------------------------")
        do {
            var teamsRequest = Afcon_TeamsRequest()
            teamsRequest.leagueID = 6
            teamsRequest.season = 2025

            let teamsResponse = try await client.getTeams(teamsRequest)
            logger.info("✅ Found \(teamsResponse.teams.count) teams:")
            for (index, teamInfo) in teamsResponse.teams.prefix(5).enumerated() {
                logger.info("   \(index + 1). \(teamInfo.team.name) (\(teamInfo.team.country))")
            }
            if teamsResponse.teams.count > 5 {
                logger.info("   ... and \(teamsResponse.teams.count - 5) more")
            }
        } catch {
            logger.error("❌ Error: \(error)")
        }

        // Test 3: GetFixtures
        logger.info("Test 3: GetFixtures (AFCON 2025)")
        logger.info("----------------------------------")
        do {
            var fixturesRequest = Afcon_FixturesRequest()
            fixturesRequest.leagueID = 6
            fixturesRequest.season = 2025
            fixturesRequest.live = false

            let fixturesResponse = try await client.getFixtures(fixturesRequest)
            logger.info("✅ Found \(fixturesResponse.fixtures.count) fixtures")

            if !fixturesResponse.fixtures.isEmpty {
                let fixture = fixturesResponse.fixtures[0]
                logger.info("   First match: \(fixture.teams.home.name) vs \(fixture.teams.away.name)")
                logger.info("   Status: \(fixture.status.long)")
                logger.info("   Date: \(fixture.timestamp)")
            }
        } catch {
            logger.error("❌ Error: \(error)")
        }

        // Test 4: GetTeamDetails
        logger.info("Test 4: GetTeamDetails (Senegal)")
        logger.info("----------------------------------")
        do {
            var teamRequest = Afcon_TeamDetailsRequest()
            teamRequest.teamID = 1503 // Senegal's team ID

            let teamResponse = try await client.getTeamDetails(teamRequest)
            logger.info("✅ Team: \(teamResponse.team.name)")
            logger.info("   Code: \(teamResponse.team.code)")
            logger.info("   Country: \(teamResponse.team.country)")
            logger.info("   Founded: \(teamResponse.team.founded)")
            logger.info("   Venue: \(teamResponse.venue.name)")
            logger.info("   Capacity: \(teamResponse.venue.capacity)")
        } catch {
            logger.error("❌ Error: \(error)")
        }

        // Test 5: StreamLiveMatches (just test connection, will timeout if no live matches)
        logger.info("Test 5: StreamLiveMatches (will check for 10 seconds)")
        logger.info("-------------------------------------------------------")
        do {
            var liveRequest = Afcon_LiveMatchRequest()
            liveRequest.leagueID = 6

            logger.info("📡 Listening for live match updates...")

            var updateCount = 0
            let stream = client.streamLiveMatches(liveRequest)

            // Create a task with timeout
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Task 1: Listen to stream
                group.addTask {
                    for try await update in stream {
                        updateCount += 1
                        logger.info("   📢 Update #\(updateCount): Fixture \(update.fixtureID) - \(update.eventType)")
                    }
                }

                // Task 2: Timeout after 10 seconds
                group.addTask {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    logger.info("   ⏱️  Timeout reached (10 seconds)")
                    throw CancellationError()
                }

                // Wait for first task to complete or timeout
                try await group.next()
                group.cancelAll()
            }

            if updateCount == 0 {
                logger.info("   ℹ️  No live matches at the moment (this is normal)")
            }
        } catch is CancellationError {
            logger.info("   ✅ Stream test completed")
        } catch {
            logger.error("   ❌ Error: \(error)")
        }

        logger.info("=====================================")
        logger.info("✅ All tests completed!")
        logger.info("=====================================")
    }
}
