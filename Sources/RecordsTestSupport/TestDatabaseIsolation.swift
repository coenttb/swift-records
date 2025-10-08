import Dependencies
import Foundation
@testable import Records

/// Provides isolated database for each test - safe for parallel execution
public struct IsolatedTestDatabase: Sendable {
    private let setupMode: Database.TestDatabaseSetupMode

    public init(setupMode: Database.TestDatabaseSetupMode = .withReminderData) {
        self.setupMode = setupMode
    }

    /// Runs a test with an isolated database
    public func run<T>(
        _ test: @Sendable (Database.TestDatabase) async throws -> T
    ) async throws -> T {
        // Acquire a fresh database from the pool
        let database = try await Database.TestDatabasePool.shared.acquire(setupMode: setupMode)

        // Run the test
        do {
            let result = try await test(database)
            // Clean up after success
            await Database.TestDatabasePool.shared.release(database)
            return result
        } catch {
            // Clean up after failure
            await Database.TestDatabasePool.shared.release(database)
            throw error
        }
    }
}

// MARK: - Convenience Extensions

extension Database.TestDatabase {
    /// Creates an isolated database for a single test (parallel-safe)
    public static func isolated(
        setupMode: Database.TestDatabaseSetupMode = .withReminderData
    ) -> IsolatedTestDatabase {
        IsolatedTestDatabase(setupMode: setupMode)
    }
}

// MARK: - Dependency Key

private enum IsolatedDatabaseKey: DependencyKey {
    static let liveValue = IsolatedTestDatabase(setupMode: .withReminderData)
    static let testValue = liveValue
}

extension DependencyValues {
    /// Provides an isolated database for each test (parallel-safe)
    public var isolatedDatabase: IsolatedTestDatabase {
        get { self[IsolatedDatabaseKey.self] }
        set { self[IsolatedDatabaseKey.self] = newValue }
    }
}
