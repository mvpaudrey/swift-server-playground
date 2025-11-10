#!/usr/bin/env swift sh
//
//  sync-fixtures.swift
//  AFCON Database Initialization Script
//
//  Syncs fixtures from the API to the database for a specific league and season.
//
//  Usage:
//    swift sync-fixtures.swift <leagueID> <season> [competition]
//
//  Examples:
//    swift sync-fixtures.swift 2 2025 "UEFA Champions League"
//    swift sync-fixtures.swift 39 2024 "Premier League"
//    swift sync-fixtures.swift 6 2024 "Africa Cup of Nations"
//
//  Common League IDs:
//    2   - UEFA Champions League
//    6   - AFCON (Africa Cup of Nations)
//    39  - Premier League
//    140 - La Liga
//    78  - Bundesliga
//    135 - Serie A
//    61  - Ligue 1
//
//  Prerequisites:
//    - Server must be running on localhost:50051
//    - Database must be accessible and migrated
//
//  Dependencies:
//    This script requires the server to be built and running.
//    Run: ./start-server.sh (in another terminal)
//

import Foundation

// MARK: - Configuration

struct Config {
    static let grpcHost = "localhost"
    static let grpcPort = 50051
    static let timeout: TimeInterval = 30.0
}

// MARK: - Models

struct SyncRequest: Codable {
    let leagueID: Int
    let season: Int
    let competition: String
}

struct SyncResponse: Codable {
    let success: Bool
    let message: String
    let fixturesCount: Int?
}

// MARK: - gRPC Helper (Using grpcurl)

class FixtureSyncer {
    let host: String
    let port: Int

    init(host: String = Config.grpcHost, port: Int = Config.grpcPort) {
        self.host = host
        self.port = port
    }

    func syncFixtures(leagueID: Int, season: Int, competition: String) throws {
        print("🔄 Syncing fixtures for \(competition) (League ID: \(leagueID), Season: \(season))...")
        print("📡 Connecting to gRPC server at \(host):\(port)...\n")

        // Check if grpcurl is installed
        let grpcurlCheck = shell("which grpcurl")
        guard !grpcurlCheck.isEmpty else {
            throw SyncError.grpcurlNotInstalled
        }

        // Find the proto file
        let protoPath = findProtoFile()
        guard !protoPath.isEmpty else {
            throw SyncError.protoFileNotFound
        }

        // Build the grpcurl command with proto file
        let jsonData = """
        {
          "league_id": \(leagueID),
          "season": \(season),
          "competition": "\(competition)"
        }
        """

        let command = """
        grpcurl -plaintext -import-path "\(protoPath)" -proto afcon.proto -d '\(jsonData)' \(host):\(port) afcon.AFCONService/SyncFixtures
        """

        print("📤 Sending sync request...")
        print("   League: \(competition)")
        print("   Season: \(season)")
        print("   ID: \(leagueID)\n")

        let output = shell(command)

        if output.contains("error") || output.contains("Error") {
            print("❌ Sync failed:")
            print(output)
            throw SyncError.syncFailed(output)
        }

        print("✅ Sync completed successfully!")
        print("\nResponse:")
        print(output)
    }

    private func findProtoFile() -> String {
        // Try to find the Protos directory
        let possiblePaths = [
            "/Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync/Protos",
            "../Protos",
            "./Protos",
            "Protos"
        ]

        for path in possiblePaths {
            let fullPath = (path as NSString).expandingTildeInPath
            let protoFile = (fullPath as NSString).appendingPathComponent("afcon.proto")

            if FileManager.default.fileExists(atPath: protoFile) {
                return fullPath
            }
        }

        return ""
    }

    private func shell(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.standardInput = nil

        task.launch()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

enum SyncError: Error, CustomStringConvertible {
    case invalidArguments
    case grpcurlNotInstalled
    case protoFileNotFound
    case syncFailed(String)
    case serverNotRunning

    var description: String {
        switch self {
        case .invalidArguments:
            return "Invalid arguments. Usage: swift sync-fixtures.swift <leagueID> <season> [competition]"
        case .grpcurlNotInstalled:
            return """
            grpcurl is not installed. Install it with:
              brew install grpcurl

            Or use the alternative curl method (see script comments).
            """
        case .protoFileNotFound:
            return """
            Proto file not found. Expected location:
              /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync/Protos/afcon.proto

            Make sure the proto file exists in the Protos directory.
            """
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        case .serverNotRunning:
            return "Server is not running. Start it with: ./start-server.sh"
        }
    }
}

// MARK: - League Presets

struct LeaguePreset {
    let id: Int
    let name: String
    let defaultSeason: Int

    static let presets: [LeaguePreset] = [
        LeaguePreset(id: 2, name: "UEFA Champions League", defaultSeason: 2025),
        LeaguePreset(id: 6, name: "Africa Cup of Nations", defaultSeason: 2024),
        LeaguePreset(id: 39, name: "Premier League", defaultSeason: 2024),
        LeaguePreset(id: 140, name: "La Liga", defaultSeason: 2024),
        LeaguePreset(id: 78, name: "Bundesliga", defaultSeason: 2024),
        LeaguePreset(id: 135, name: "Serie A", defaultSeason: 2024),
        LeaguePreset(id: 61, name: "Ligue 1", defaultSeason: 2024),
    ]

    static func find(id: Int) -> LeaguePreset? {
        return presets.first { $0.id == id }
    }
}

// MARK: - Main Script

func printUsage() {
    print("""

    ⚽ AFCON Fixture Sync Script
    ============================

    Usage:
      swift sync-fixtures.swift <leagueID> <season> [competition]

    Arguments:
      leagueID     - The league ID to sync (required)
      season       - The season year (required, e.g., 2024, 2025)
      competition  - The competition name (optional, auto-detected if omitted)

    Examples:
      swift sync-fixtures.swift 2 2025
      swift sync-fixtures.swift 39 2024 "Premier League"
      swift sync-fixtures.swift 6 2024 "Africa Cup of Nations"

    Common League IDs:
      2   - UEFA Champions League
      6   - AFCON (Africa Cup of Nations)
      39  - Premier League
      140 - La Liga
      78  - Bundesliga
      135 - Serie A
      61  - Ligue 1

    Prerequisites:
      • Server running on localhost:50051
      • grpcurl installed (brew install grpcurl)
      • Database accessible and migrated

    """)
}

func main() {
    let args = CommandLine.arguments

    // Check for help flag
    if args.contains("-h") || args.contains("--help") {
        printUsage()
        exit(0)
    }

    // Parse arguments
    guard args.count >= 3 else {
        print("❌ Error: Missing required arguments\n")
        printUsage()
        exit(1)
    }

    guard let leagueID = Int(args[1]) else {
        print("❌ Error: Invalid league ID '\(args[1])'. Must be a number.\n")
        printUsage()
        exit(1)
    }

    guard let season = Int(args[2]) else {
        print("❌ Error: Invalid season '\(args[2])'. Must be a year (e.g., 2024).\n")
        printUsage()
        exit(1)
    }

    // Determine competition name
    let competition: String
    if args.count >= 4 {
        competition = args[3]
    } else if let preset = LeaguePreset.find(id: leagueID) {
        competition = preset.name
        print("ℹ️  Auto-detected competition: \(competition)\n")
    } else {
        competition = "League \(leagueID)"
        print("⚠️  Unknown league ID. Using generic name: \(competition)\n")
    }

    // Run sync
    do {
        let syncer = FixtureSyncer()
        try syncer.syncFixtures(leagueID: leagueID, season: season, competition: competition)

        print("\n🎉 Database successfully initialized with \(competition) fixtures!")
        print("   You can now use the API to fetch fixtures for this league.\n")

    } catch let error as SyncError {
        print("\n❌ Error: \(error.description)\n")
        exit(1)
    } catch {
        print("\n❌ Unexpected error: \(error.localizedDescription)\n")
        exit(1)
    }
}

// Run the script
main()
