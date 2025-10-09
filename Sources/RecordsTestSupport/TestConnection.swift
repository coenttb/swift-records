import Foundation
import Logging
import NIOCore
import NIOPosix
import PostgresNIO
@testable import Records

/// Global EventLoopGroup for all test clients
/// Following PostgresNIO's pattern: one shared EventLoopGroup, shutdown in teardown
private let testEventLoopGroup = MultiThreadedEventLoopGroup.singleton

/// Global task manager for test client lifecycle
private actor TestClientManager {
    private var clients: [(PostgresClient, Task<Void, Never>)] = []

    func register(client: PostgresClient, runTask: Task<Void, Never>) {
        clients.append((client, runTask))
    }

    func shutdownAll() async {
        // Cancel all run tasks
        for (_, task) in clients {
            task.cancel()
        }

        // Wait for cancellation to complete
        for (_, task) in clients {
            await task.value
        }

        // Shutdown the EventLoopGroup - THIS IS THE KEY from PostgresNIO tests!
        try? await testEventLoopGroup.shutdownGracefully()

        clients.removeAll()
    }
}

private let testClientManager = TestClientManager()

/// Register shutdown handler on first use
private nonisolated(unsafe) var shutdownHandlerRegistered = false

/// Test database connection using PostgresClient with structured concurrency
///
/// Implements the pattern from PostgresNIO's own test suite:
/// - PostgresClient.run() runs in a child Task
/// - Graceful shutdown via task cancellation
/// - Process exits cleanly after tests complete
final class TestConnection: Database.Writer, @unchecked Sendable {
    private let client: PostgresClient
    private let runTask: Task<Void, Never>

    init(configuration: PostgresClient.Configuration) async {
        // Create PostgresClient with shared EventLoopGroup (like PostgresNIO tests)
        let client = PostgresClient(
            configuration: configuration,
            eventLoopGroup: testEventLoopGroup,
            backgroundLogger: Logger(label: "test-db")
        )
        self.client = client

        // Start client.run() in a task (like PostgresNIO tests do)
        // Capture client directly, not self
        let runTask = Task {
            await client.run()
        }
        self.runTask = runTask

        // Register with manager for shutdown
        await testClientManager.register(client: client, runTask: runTask)

        // Register shutdown handler on first client creation
        if !shutdownHandlerRegistered {
            shutdownHandlerRegistered = true
            // Use atexit to ensure cleanup happens on process exit
            atexit {
                // Run async shutdown synchronously via runloop
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    await testClientManager.shutdownAll()
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + .seconds(5))
            }
        }

        // Give client a moment to initialize
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }

    func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await client.withConnection { postgresConnection in
            let connection = Database.Connection(postgresConnection)
            return try await block(connection)
        }
    }

    func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await client.withConnection { postgresConnection in
            let connection = Database.Connection(postgresConnection)
            return try await block(connection)
        }
    }

    func close() async throws {
        // Shutdown handled by global manager
    }
}
