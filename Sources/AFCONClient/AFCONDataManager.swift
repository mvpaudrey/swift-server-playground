import Foundation

/// Minimal data manager for AFCON data
/// Provides simple access to the gRPC service
@MainActor
public final class AFCONDataManager: ObservableObject {
    public let service: AFCONService

    @Published public var isLoading = false
    @Published public var lastError: (any Error)?

    public init() throws {
        self.service = try AFCONService()
    }

    // Users of this library can call service methods directly
    // Example: let leagues = try await dataManager.service.getLeague(leagueId: 6, season: 2025)
}
