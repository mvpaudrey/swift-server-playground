// NotificationService.swift
// TODO: Requires APNSwift v5+ migration for Swift 6 compatibility
// Temporarily disabled - uncomment and migrate when needed

#if false

// Original code commented out - requires APNSwift update
// See SWIFT6_MIGRATION_COMPLETE.md for details

#endif

import Foundation
import Vapor
import Fluent

/// Placeholder notification service - real implementation requires APNSwift migration
public actor NotificationService {
    private let db: any Database
    private let logger: Logger
    
    public init(db: any Database, logger: Logger, app: Application) async throws {
        self.db = db
        self.logger = logger
        logger.warning("⚠️ NotificationService is disabled - requires APNSwift v5+ migration")
    }
}
