import Dependencies
import EnvironmentVariables
import Foundation
import PostgresNIO
import StructuredQueriesPostgres

// MARK: - Database.Configuration

extension Database {
    /// Errors that can occur during configuration.
    public enum ConfigurationError: Error, CustomStringConvertible {
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
    public struct Configuration: Sendable {
        /// The host to connect to.
        public let host: String
        
        /// The port to connect to.
        public let port: Int
        
        /// The database name.
        public let database: String
        
        /// The username for authentication.
        public let username: String
        
        /// The password for authentication.
        public let password: String?
        
        /// TLS configuration.
        public let tls: PostgresConnection.Configuration.TLS
        
        /// Connection strategy.
        public let connectionStrategy: ConnectionStrategy
        
        /// Maximum connection lifetime in seconds.
        public let maxConnectionLifetime: TimeInterval?
        
        /// Connection timeout in seconds.
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
        
        /// Create configuration from environment variables.
        ///
        /// Looks for the following environment variables:
        /// - DATABASE_HOST or POSTGRES_HOST (required)
        /// - DATABASE_PORT or POSTGRES_PORT (required)
        /// - DATABASE_NAME or POSTGRES_DB (required)
        /// - DATABASE_USER or POSTGRES_USER (required)
        /// - DATABASE_PASSWORD or POSTGRES_PASSWORD (optional)
        ///
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
        
        /// Convert to PostgresQueryDatabase.Configuration
        internal var postgresConfiguration: PostgresQueryDatabase.Configuration {
            let pooling: PostgresQueryDatabase.Configuration.PoolingStrategy
            switch connectionStrategy {
            case .single:
                pooling = .disabled
            case let .pool(min, max):
                pooling = .enabled(min: min, max: max)
            }
            
            return PostgresQueryDatabase.Configuration(
                host: host,
                port: port,
                database: database,
                username: username,
                password: password,
                tls: tls,
                pooling: pooling
            )
        }
    }
}

// MARK: - Database.Configuration.ConnectionStrategy

extension Database.Configuration {
    /// Connection strategy for the database.
    public enum ConnectionStrategy: Sendable {
        /// Use a single database connection.
        case single
        /// Use a connection pool with min and max connections.
        case pool(min: Int = 2, max: Int = 10)
    }
}