import Foundation

/// The main namespace for database-related types and functionality.
///
/// `Database` serves as a namespace for all database-related types in the Records library.
/// It provides types for connection management, configuration, and database operations.
///
/// ## Topics
///
/// ### Connection Types
/// - ``Queue``: Serial database access with a single connection
/// - ``Pool``: Concurrent database access with connection pooling
///
/// ### Protocols
/// - ``Reader``: Read-only database access
/// - ``Writer``: Read-write database access
///
/// ### Configuration
/// - ``Configuration``: Database connection configuration
/// - ``Error``: Database-specific errors
///
/// ## Setup
///
/// Configure the database dependency at your app's entry point:
///
/// ```swift
/// import Dependencies
/// import Records
///
/// @main
/// struct MyApp {
///     static func main() async throws {
///         // Configure database at startup
///         try await prepareDependencies {
///             $0.defaultDatabase = try await Database.Pool(
///                 configuration: .fromEnvironment(),
///                 minConnections: 5,
///                 maxConnections: 20
///             )
///         }
///         
///         // Run your app
///     }
/// }
/// ```
///
/// ## Usage
///
/// Once configured, access the database via dependency injection:
///
/// ```swift
/// import Dependencies
/// import Records
///
/// struct UserService {
///     @Dependency(\.defaultDatabase) var db
///     
///     func fetchUsers() async throws -> [User] {
///         try await db.read { db in
///             try await User.fetchAll(db)
///         }
///     }
///     
///     func createUser(name: String, email: String) async throws {
///         try await db.write { db in
///             try await User.insert {
///                 ($0.name, $0.email, $0.createdAt)
///             } values: {
///                 (name, email, Date())
///             }.execute(db)
///         }
///     }
/// }
/// ```
public enum Database {
    // Namespace holder - never instantiated
}