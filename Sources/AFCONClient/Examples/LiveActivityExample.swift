import Foundation
import ActivityKit
import SwiftUI

// MARK: - Live Activity Attributes & Content State

/// Defines the static and dynamic content for AFCON match Live Activities
@available(iOS 16.1, *)
struct AFCONMatchAttributes: ActivityAttributes {
    public typealias ContentState = AFCONMatchContentState

    // Static data (doesn't change during the activity)
    public struct ContentState: Codable, Hashable {
        var homeTeam: String
        var awayTeam: String
        var homeScore: Int
        var awayScore: Int
        var status: String  // "NS", "1H", "HT", "2H", "ET", "FT"
        var elapsed: Int
        var lastEvent: String?
        var updatedAt: Date
    }

    // Static attributes
    var fixtureId: Int
    var homeTeamLogo: String
    var awayTeamLogo: String
}

// MARK: - Live Activity Manager

@available(iOS 16.1, *)
@MainActor
class AFCONLiveActivityManager: ObservableObject {
    @Published var activeActivities: [Int: Activity<AFCONMatchAttributes>] = [:]

    private let grpcClient: AFCONService
    private var deviceUUID: String?

    init(grpcClient: AFCONService) {
        self.grpcClient = grpcClient
    }

    /// Register device and get UUID from server
    func registerDevice(apnsToken: String, platform: String = "ios") async throws {
        var request = Afcon_RegisterDeviceRequest()
        request.userID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        request.deviceToken = apnsToken
        request.platform = platform
        request.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? ""
        request.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        request.osVersion = UIDevice.current.systemVersion
        request.language = Locale.current.language.languageCode?.identifier ?? "en"
        request.timezone = TimeZone.current.identifier

        let response = try await grpcClient.registerDevice(request: request)

        if response.success {
            self.deviceUUID = response.deviceUuid
            print("✅ Device registered with UUID: \(response.deviceUuid)")
        } else {
            throw NSError(domain: "AFCONLiveActivity", code: 1, userInfo: [
                NSLocalizedDescriptionKey: response.message
            ])
        }
    }

    /// Start a Live Activity for a match
    func startLiveActivity(
        fixtureId: Int,
        homeTeam: String,
        awayTeam: String,
        homeTeamLogo: String,
        awayTeamLogo: String,
        initialScore: (home: Int, away: Int) = (0, 0)
    ) async throws -> Activity<AFCONMatchAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are disabled")
            return nil
        }

        guard let deviceUUID = deviceUUID else {
            throw NSError(domain: "AFCONLiveActivity", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Device not registered. Call registerDevice() first."
            ])
        }

        // Create attributes and initial state
        let attributes = AFCONMatchAttributes(
            fixtureId: fixtureId,
            homeTeamLogo: homeTeamLogo,
            awayTeamLogo: awayTeamLogo
        )

        let initialState = AFCONMatchAttributes.ContentState(
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeScore: initialScore.home,
            awayScore: initialScore.away,
            status: "NS",
            elapsed: 0,
            lastEvent: nil,
            updatedAt: Date()
        )

        // Start the activity locally
        let activity = try Activity<AFCONMatchAttributes>.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil),
            pushType: .token
        )

        // Wait for push token
        for await pushToken in activity.pushTokenUpdates {
            let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()

            // Register with server
            var request = Afcon_StartLiveActivityRequest()
            request.deviceUuid = deviceUUID
            request.fixtureID = Int32(fixtureId)
            request.activityID = activity.id
            request.pushToken = tokenString
            request.updateFrequency = "major_events"  // goals, red cards, VAR, penalties

            let response = try await grpcClient.startLiveActivity(request: request)

            if response.success {
                activeActivities[fixtureId] = activity
                print("✅ Live Activity started for fixture \(fixtureId)")
                print("   Activity ID: \(activity.id)")
                print("   Server UUID: \(response.activityUuid)")
            } else {
                print("❌ Failed to register Live Activity with server: \(response.message)")
            }

            break  // Only need the first token
        }

        return activity
    }

    /// Update Live Activity manually (usually updates come via push)
    func updateActivity(fixtureId: Int, newState: AFCONMatchAttributes.ContentState) async {
        guard let activity = activeActivities[fixtureId] else {
            print("⚠️ No active activity for fixture \(fixtureId)")
            return
        }

        await activity.update(.init(state: newState, staleDate: nil))
    }

    /// End a Live Activity
    func endActivity(fixtureId: Int, finalState: AFCONMatchAttributes.ContentState? = nil) async {
        guard let activity = activeActivities[fixtureId] else {
            print("⚠️ No active activity for fixture \(fixtureId)")
            return
        }

        if let finalState = finalState {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
        } else {
            await activity.end(nil, dismissalPolicy: .default)
        }

        activeActivities.removeValue(forKey: fixtureId)
        print("✅ Live Activity ended for fixture \(fixtureId)")
    }

    /// Clean up all active activities
    func endAllActivities() async {
        for (fixtureId, activity) in activeActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("✅ Ended activity for fixture \(fixtureId)")
        }
        activeActivities.removeAll()
    }
}

// MARK: - Live Activity UI (for Lock Screen & Dynamic Island)

@available(iOS 16.1, *)
struct AFCONMatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AFCONMatchAttributes.self) { context in
            // Lock Screen UI
            AFCONMatchLockScreenView(context: context)
        } dynamicIsland: { context in
            // Dynamic Island UI
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        AsyncImage(url: URL(string: context.attributes.homeTeamLogo)) { image in
                            image.resizable()
                        } placeholder: {
                            Circle().fill(.gray)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())

                        VStack(alignment: .leading) {
                            Text(context.state.homeTeam)
                                .font(.headline)
                            Text("\(context.state.homeScore)")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack {
                        VStack(alignment: .trailing) {
                            Text(context.state.awayTeam)
                                .font(.headline)
                            Text("\(context.state.awayScore)")
                                .font(.title)
                                .fontWeight(.bold)
                        }

                        AsyncImage(url: URL(string: context.attributes.awayTeamLogo)) { image in
                            image.resizable()
                        } placeholder: {
                            Circle().fill(.gray)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.status) - \(context.state.elapsed)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if let lastEvent = context.state.lastEvent {
                        Text(lastEvent)
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.vertical, 4)
                    }
                }
            } compactLeading: {
                // Compact leading (left side of notch)
                Text("\(context.state.homeScore)")
                    .font(.caption)
                    .fontWeight(.bold)
            } compactTrailing: {
                // Compact trailing (right side of notch)
                Text("\(context.state.awayScore)")
                    .font(.caption)
                    .fontWeight(.bold)
            } minimal: {
                // Minimal view (single icon)
                Image(systemName: "sportscourt.fill")
            }
        }
    }
}

@available(iOS 16.1, *)
struct AFCONMatchLockScreenView: View {
    let context: ActivityViewContext<AFCONMatchAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                AsyncImage(url: URL(string: context.attributes.homeTeamLogo)) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(.gray)
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())

                Text(context.state.homeTeam)
                    .font(.headline)

                Spacer()

                Text("\(context.state.homeScore)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack {
                AsyncImage(url: URL(string: context.attributes.awayTeamLogo)) { image in
                    image.resizable()
                } placeholder: {
                    Circle().fill(.gray)
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())

                Text(context.state.awayTeam)
                    .font(.headline)

                Spacer()

                Text("\(context.state.awayScore)")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            HStack {
                Text("\(context.state.status) - \(context.state.elapsed)'")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastEvent = context.state.lastEvent {
                    Text("• \(lastEvent)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }
}

// MARK: - Example Usage in Your App

@available(iOS 16.1, *)
struct MatchDetailView: View {
    let fixture: FixtureData
    @StateObject private var liveActivityManager: AFCONLiveActivityManager
    @State private var hasStartedActivity = false

    init(fixture: FixtureData, grpcClient: AFCONService) {
        self.fixture = fixture
        _liveActivityManager = StateObject(wrappedValue: AFCONLiveActivityManager(grpcClient: grpcClient))
    }

    var body: some View {
        VStack {
            Text("\(fixture.homeTeamName) vs \(fixture.awayTeamName)")
                .font(.title)

            if !hasStartedActivity {
                Button("Start Live Activity") {
                    Task {
                        do {
                            _ = try await liveActivityManager.startLiveActivity(
                                fixtureId: fixture.id,
                                homeTeam: fixture.homeTeamName,
                                awayTeam: fixture.awayTeamName,
                                homeTeamLogo: fixture.homeTeamLogoURL,
                                awayTeamLogo: fixture.awayTeamLogoURL,
                                initialScore: (fixture.homeGoals, fixture.awayGoals)
                            )
                            hasStartedActivity = true
                        } catch {
                            print("Failed to start Live Activity: \(error)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("End Live Activity") {
                    Task {
                        await liveActivityManager.endActivity(fixtureId: fixture.id)
                        hasStartedActivity = false
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Supporting Types

struct FixtureData {
    let id: Int
    let homeTeamName: String
    let awayTeamName: String
    let homeTeamLogoURL: String
    let awayTeamLogoURL: String
    let homeGoals: Int
    let awayGoals: Int
}
