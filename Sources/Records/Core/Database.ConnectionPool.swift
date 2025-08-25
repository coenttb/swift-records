import Foundation
import PostgresNIO
import Logging

extension Database {
    /// Connection pool for managing multiple PostgreSQL connections
    actor ConnectionPool: Sendable {
        private var available: [PostgresConnection] = []
        private var inUse: Set<ObjectIdentifier> = []
        private let configuration: PostgresConnection.Configuration
        private let minConnections: Int
        private let maxConnections: Int
        private var totalConnections: Int = 0
        private var isShuttingDown: Bool = false
        
        init(
            configuration: PostgresConnection.Configuration,
            minConnections: Int,
            maxConnections: Int
        ) async throws {
            self.configuration = configuration
            self.minConnections = minConnections
            self.maxConnections = maxConnections
            
            // Create initial connections
            for i in 0..<minConnections {
                let connection = try await createConnection(id: i)
                available.append(connection)
                totalConnections += 1
            }
        }
        
        func withConnection<T: Sendable>(
            _ operation: @Sendable (PostgresConnection) async throws -> T
        ) async throws -> T {
            let connection = try await checkoutConnection()
            
            do {
                let result = try await operation(connection)
                try await checkinConnection(connection)
                return result
            } catch {
                // Return connection to pool even on error
                // PostgreSQL automatically rolls back failed transactions,
                // so the connection should be clean for most error cases.
                // Only network/protocol errors would truly corrupt a connection,
                // and those would fail the checkin attempt anyway.
                try? await checkinConnection(connection)
                throw error
            }
        }
        
        func checkoutConnection() async throws -> PostgresConnection {
            guard !isShuttingDown else {
                throw Database.Error.poolShuttingDown
            }
            
            // Try to get an available connection
            if let connection = available.popLast() {
                inUse.insert(ObjectIdentifier(connection))
                return connection
            }
            
            // Create a new connection if under max limit
            if totalConnections < maxConnections {
                let connection = try await createConnection(id: totalConnections)
                totalConnections += 1
                inUse.insert(ObjectIdentifier(connection))
                return connection
            }
            
            // Wait for a connection to become available
            while available.isEmpty && !isShuttingDown {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            guard !isShuttingDown else {
                throw Database.Error.poolShuttingDown
            }
            
            guard let connection = available.popLast() else {
                throw Database.Error.poolExhausted(maxConnections: maxConnections)
            }
            
            inUse.insert(ObjectIdentifier(connection))
            return connection
        }
        
        func checkinConnection(_ connection: PostgresConnection) async throws {
            let id = ObjectIdentifier(connection)
            guard inUse.contains(id) else { return }
            
            inUse.remove(id)
            
            // Don't return to pool if shutting down
            if isShuttingDown {
                try await connection.close()
                totalConnections -= 1
            } else {
                available.append(connection)
            }
        }
        
        func shutdown() async throws {
            isShuttingDown = true
            
            // Close all available connections
            for connection in available {
                try await connection.close()
            }
            available.removeAll()
            
            // Note: in-use connections will be closed when checked back in
        }
        
        private func createConnection(id: Int) async throws -> PostgresConnection {
            try await PostgresConnection.connect(
                configuration: configuration,
                id: id,
                logger: Logger(label: "postgres.pool.\(id)")
            )
        }
    }
}