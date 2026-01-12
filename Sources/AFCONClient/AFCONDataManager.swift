import Foundation
#if canImport(Combine)
import Combine
#endif

/// Minimal data manager for AFCON data
/// Provides simple access to the gRPC service
@MainActor
public final class AFCONDataManager {
    public let service: AFCONService

#if canImport(Combine)
    @Published public var isLoading = false
    @Published public var lastError: (any Error)?
#else
    public var isLoading = false
    public var lastError: (any Error)?
#endif

    public init() throws {
        self.service = try AFCONService()
    }

    // Users of this library can call service methods directly
    // Example: let leagues = try await dataManager.service.getLeague(leagueId: 6, season: 2025)
}

#if canImport(Combine)
extension AFCONDataManager: ObservableObject {}
#endif
