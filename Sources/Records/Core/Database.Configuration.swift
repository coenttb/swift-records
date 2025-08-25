import Dependencies
import EnvironmentVariables
import Foundation
import PostgresNIO

// MARK: - Database.Configuration

extension Database {
    /// Errors that can occur during configuration.
    public enum ConfigurationError: Swift.Error, CustomStringConvertible {
        case missingEnvironmentVariable(String)
        case invalidPort(String)
        
        public var description: String {
            switch self {
            case let .missingEnvironmentVariable(key):
                return "Missing required environment variable: \(key)"
            case let .invalidPort(value):
                return "Invalid port value: \(value)"
            }
        }
    }
    
    /// Configuration for database connections.
    ///
    /// Use this to configure database connection parameters including
    /// host, port, credentials, and connection pooling strategy.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Manual configuration
    /// let config = Database.Configuration(
    ///     host: "localhost",
    ///     port: 5432,
    ///     database: "myapp",
    ///     username: "postgres",
    ///     password: "secret",
    ///     connectionStrategy: .pool(min: 5, max: 20)
    /// )
    ///
    /// // From environment variables
    /// let config = try Database.Configuration.fromEnvironment(
    ///     connectionStrategy: .pool(min: 5, max: 20)
    /// )
    /// ```
    public struct Configuration: Sendable {
        /// The host to connect to.
        /// Typically "localhost" for development or a domain/IP for production.
        public let host: String
        
        /// The port to connect to.
        /// PostgreSQL default is 5432.
        public let port: Int
        
        /// The database name.
        /// The specific database to connect to on the PostgreSQL server.
        public let database: String
        
        /// The username for authentication.
        public let username: String
        
        /// The password for authentication.
        /// Optional as some configurations may use other auth methods.
        public let password: String?
        
        /// TLS configuration.
        /// Controls whether to use SSL/TLS for the connection.
        public let tls: PostgresConnection.Configuration.TLS
        
        /// Connection strategy.
        /// Determines whether to use a single connection or a pool.
        public let connectionStrategy: ConnectionStrategy
        
        /// Maximum connection lifetime in seconds.
        /// Connections older than this are replaced. Nil means no limit.
        public let maxConnectionLifetime: TimeInterval?
        
        /// Connection timeout in seconds.
        /// How long to wait when establishing a connection.
        public let connectionTimeout: TimeInterval
        
        public init(
            host: String,
            port: Int = 5432,
            database: String,
            username: String,
            password: String? = nil,
            tls: PostgresConnection.Configuration.TLS = .disable,
            connectionStrategy: ConnectionStrategy = .single,
            maxConnectionLifetime: TimeInterval? = nil,
            connectionTimeout: TimeInterval = 10
        ) {
            self.host = host
            self.port = port
            self.database = database
            self.username = username
            self.password = password
            self.tls = tls
            self.connectionStrategy = connectionStrategy
            self.maxConnectionLifetime = maxConnectionLifetime
            self.connectionTimeout = connectionTimeout
        }
        
        /// Creates configuration from environment variables.
        ///
        /// Looks for the following environment variables:
        /// - `DATABASE_HOST` or `POSTGRES_HOST` (required)
        /// - `DATABASE_PORT` or `POSTGRES_PORT` (required)
        /// - `DATABASE_NAME` or `POSTGRES_DB` (required)
        /// - `DATABASE_USER` or `POSTGRES_USER` (required)
        /// - `DATABASE_PASSWORD` or `POSTGRES_PASSWORD` (optional)
        ///
        /// ## Example
        ///
        /// ```bash
        /// # Set environment variables
        /// export DATABASE_HOST=localhost
        /// export DATABASE_PORT=5432
        /// export DATABASE_NAME=myapp
        /// export DATABASE_USER=postgres
        /// export DATABASE_PASSWORD=secret
        /// ```
        ///
        /// ```swift
        /// // In your app
        /// let config = try Database.Configuration.fromEnvironment(
        ///     connectionStrategy: .pool(min: 5, max: 20)
        /// )
        /// ```
        ///
        /// - Parameter connectionStrategy: The connection strategy to use.
        /// - Returns: A configuration built from environment variables.
        /// - Throws: ``ConfigurationError`` if required environment variables are missing or invalid.
        public static func fromEnvironment(
            connectionStrategy: ConnectionStrategy = .single
        ) throws -> Configuration {
            @Dependency(\.envVars) var envVars
            
            // Get host
            guard let host = envVars["DATABASE_HOST"] ?? envVars["POSTGRES_HOST"] else {
                throw ConfigurationError.missingEnvironmentVariable("DATABASE_HOST or POSTGRES_HOST")
            }
            
            // Get port
            let portString = envVars["DATABASE_PORT"] ?? envVars["POSTGRES_PORT"]
            guard let portString else {
                throw ConfigurationError.missingEnvironmentVariable("DATABASE_PORT or POSTGRES_PORT")
            }
            guard let port = Int(portString) else {
                throw ConfigurationError.invalidPort(portString)
            }
            
            // Get database name
            guard let database = envVars["DATABASE_NAME"] ?? envVars["POSTGRES_DB"] else {
                throw ConfigurationError.missingEnvironmentVariable("DATABASE_NAME or POSTGRES_DB")
            }
            
            // Get username
            guard let username = envVars["DATABASE_USER"] ?? envVars["POSTGRES_USER"] else {
                throw ConfigurationError.missingEnvironmentVariable("DATABASE_USER or POSTGRES_USER")
            }
            
            // Password is optional
            let password = envVars["DATABASE_PASSWORD"] ?? envVars["POSTGRES_PASSWORD"]
            
            return Configuration(
                host: host,
                port: port,
                database: database,
                username: username,
                password: password,
                connectionStrategy: connectionStrategy
            )
        }
        
    }
}

// MARK: - Database.Configuration.ConnectionStrategy

extension Database.Configuration {
    /// Connection strategy for the database.
    ///
    /// Determines whether to use a single connection or a connection pool.
    ///
    /// ## Choosing a Strategy
    ///
    /// - Use `.single` for:
    ///   - Development and testing
    ///   - Applications with low concurrency
    ///   - Batch processing jobs
    ///
    /// - Use `.pool` for:
    ///   - Production web applications
    ///   - High concurrency scenarios
    ///   - Applications that benefit from connection reuse
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Single connection
    /// let config = Database.Configuration(
    ///     host: "localhost",
    ///     database: "myapp",
    ///     username: "postgres",
    ///     connectionStrategy: .single
    /// )
    ///
    /// // Connection pool
    /// let config = Database.Configuration(
    ///     host: "localhost",
    ///     database: "myapp",
    ///     username: "postgres",
    ///     connectionStrategy: .pool(min: 5, max: 20)
    /// )
    /// ```
    public enum ConnectionStrategy: Sendable {
        /// Use a single database connection.
        /// Best for development or low-concurrency scenarios.
        case single
        
        /// Use a connection pool with min and max connections.
        /// - Parameters:
        ///   - min: Minimum number of connections to maintain (default: 2)
        ///   - max: Maximum number of connections allowed (default: 10)
        case pool(min: Int = 2, max: Int = 10)
    }
}
