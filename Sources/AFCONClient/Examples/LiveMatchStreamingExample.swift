import Foundation
import SwiftUI
import GRPCCore
import GRPCNIOTransportHTTP2

// MARK: - Example 1: Basic gRPC Streaming for Live Matches

/// Example view model showing how to use gRPC streaming in your iOS app
@available(iOS 18.0, macOS 15.0, *)
@MainActor
class LiveMatchViewModel: ObservableObject {
    @Published var liveMatches: [LiveMatchData] = []
    @Published var isStreaming = false
    @Published var error: String?

    private var streamTask: Task<Void, Never>?
    private let grpcClient: AFCONService

    init(serverHost: String = "localhost", serverPort: Int = 50051) {
        // Initialize gRPC client
        self.grpcClient = try! AFCONService(
            host: serverHost,
            port: serverPort,
            useTLS: false
        )
    }

    /// Start streaming live matches for a league
    func startStreaming(leagueId: Int = 6, season: Int = 2025) {
        // Cancel existing stream if any
        stopStreaming()

        isStreaming = true
        error = nil

        streamTask = Task {
            do {
                // Create streaming request
                var request = Afcon_LiveMatchRequest()
                request.leagueID = Int32(leagueId)
                request.season = Int32(season)

                // Start streaming - this is a long-lived connection
                let stream = try await grpcClient.streamLiveMatches(request: request)

                // Process updates as they arrive
                for try await update in stream {
                    await handleLiveUpdate(update)
                }

            } catch {
                await MainActor.run {
                    self.error = "Stream error: \(error.localizedDescription)"
                    self.isStreaming = false
                }
            }
        }
    }

    /// Stop the live match stream
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    /// Handle incoming live match updates
    private func handleLiveUpdate(_ update: Afcon_LiveMatchUpdate) {
        let fixture = update.fixture

        // Find or create match data
        if let index = liveMatches.firstIndex(where: { $0.id == fixture.id }) {
            // Update existing match
            liveMatches[index] = LiveMatchData(from: fixture, lastEvent: update.eventType)
        } else {
            // Add new live match
            liveMatches.append(LiveMatchData(from: fixture, lastEvent: update.eventType))
        }

        // Remove finished matches
        liveMatches.removeAll { $0.status == "FT" || $0.status == "AET" || $0.status == "PEN" }

        print("📺 Live update: \(fixture.teams.home.name) \(fixture.goals.home) - \(fixture.goals.away) \(fixture.teams.away.name) (\(fixture.status.short))")
    }

    deinit {
        stopStreaming()
    }
}

// MARK: - Supporting Types

@available(iOS 18.0, macOS 15.0, *)
struct LiveMatchData: Identifiable {
    let id: Int
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let status: String
    let elapsed: Int
    let lastEvent: String?

    init(from fixture: Afcon_Fixture, lastEvent: String?) {
        self.id = Int(fixture.id)
        self.homeTeam = fixture.teams.home.name
        self.awayTeam = fixture.teams.away.name
        self.homeScore = Int(fixture.goals.home)
        self.awayScore = Int(fixture.goals.away)
        self.status = fixture.status.short
        self.elapsed = Int(fixture.status.elapsed)
        self.lastEvent = lastEvent
    }
}

// MARK: - Example SwiftUI View

@available(iOS 18.0, macOS 15.0, *)
struct LiveMatchesView: View {
    @StateObject private var viewModel = LiveMatchViewModel()

    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isStreaming {
                    HStack {
                        ProgressView()
                        Text("Streaming live...")
                            .font(.caption)
                    }
                    .padding()
                }

                if let error = viewModel.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                }

                if viewModel.liveMatches.isEmpty {
                    ContentUnavailableView(
                        "No Live Matches",
                        systemImage: "sportscourt",
                        description: Text("There are no live matches at the moment")
                    )
                } else {
                    List(viewModel.liveMatches) { match in
                        LiveMatchRow(match: match)
                    }
                }
            }
            .navigationTitle("Live Matches")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(viewModel.isStreaming ? "Stop" : "Start") {
                        if viewModel.isStreaming {
                            viewModel.stopStreaming()
                        } else {
                            viewModel.startStreaming()
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.startStreaming()
        }
        .onDisappear {
            viewModel.stopStreaming()
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct LiveMatchRow: View {
    let match: LiveMatchData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(match.homeTeam)
                    .fontWeight(.medium)
                Spacer()
                Text("\(match.homeScore)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack {
                Text(match.awayTeam)
                    .fontWeight(.medium)
                Spacer()
                Text("\(match.awayScore)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack {
                Text("\(match.status) - \(match.elapsed)'")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let event = match.lastEvent {
                    Text("• \(event)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Example 2: Combine with SwiftData Caching

@available(iOS 18.0, macOS 15.0, *)
class LiveMatchWithCacheViewModel: ObservableObject {
    @Published var liveMatches: [LiveMatchData] = []

    private let grpcClient: AFCONService
    private let dataManager: AFCONDataManager
    private var streamTask: Task<Void, Never>?

    init(serverHost: String = "localhost", serverPort: Int = 50051) {
        self.grpcClient = try! AFCONService(host: serverHost, port: serverPort, useTLS: false)
        self.dataManager = AFCONDataManager(grpcService: grpcClient)
    }

    func startStreaming(leagueId: Int = 6, season: Int = 2025) async {
        streamTask = Task {
            do {
                var request = Afcon_LiveMatchRequest()
                request.leagueID = Int32(leagueId)
                request.season = Int32(season)

                let stream = try await grpcClient.streamLiveMatches(request: request)

                for try await update in stream {
                    // Update both live state and cache
                    await handleUpdate(update)
                }
            } catch {
                print("Stream error: \(error)")
            }
        }
    }

    private func handleUpdate(_ update: Afcon_LiveMatchUpdate) async {
        // Update cache in SwiftData
        await dataManager.updateFixtureFromLiveUpdate(update.fixture)

        // Update UI
        await MainActor.run {
            if let index = liveMatches.firstIndex(where: { $0.id == update.fixture.id }) {
                liveMatches[index] = LiveMatchData(from: update.fixture, lastEvent: update.eventType)
            } else {
                liveMatches.append(LiveMatchData(from: update.fixture, lastEvent: update.eventType))
            }
        }
    }
}
