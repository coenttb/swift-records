#if PostgresNIO
    public import ISO_9075_Call_Level_Interface
    public import Logging
    public import NIOPosix
    public import PostgresNIO

    extension PostgreSQL {
        public struct Database: ISO_9075.Database, Sendable {
            public let client: PostgresClient
            public let threadPool: NIOThreadPool
            public let logger: Logger

            public init(client: PostgresClient, threadPool: NIOThreadPool, logger: Logger) {
                self.client = client
                self.threadPool = threadPool
                self.logger = logger
            }

            public init(
                configuration: PostgreSQL.Configuration,
                connections: ClosedRange<Int>,
                threadPool: NIOThreadPool,
                logger: Logger
            ) {
                self.init(
                    client: PostgresClient(configuration: configuration.client(connections: connections), backgroundLogger: logger),
                    threadPool: threadPool,
                    logger: logger
                )
            }

            public func run() async {
                await client.run()
            }

            public func read<Value: Sendable>(
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await scope(begin: "BEGIN TRANSACTION READ ONLY", end: "COMMIT", body)
            }

            public func write<Value: Sendable>(
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await scope(begin: "BEGIN", end: "COMMIT", body)
            }

            public func write<Value: Sendable>(
                isolation: PostgreSQL.Isolation,
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await scope(begin: isolation.begin, end: "COMMIT", body)
            }

            public func withRollback<Value: Sendable>(
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await scope(begin: "BEGIN", end: "ROLLBACK", body)
            }

            public func writeWithoutTransaction<Value: Sendable>(
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await leased(body)
            }

            private func scope<Value: Sendable>(
                begin: ISO_9075.Fragment,
                end: ISO_9075.Fragment,
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                try await leased { connection throws(ISO_9075.Error) in
                    _ = try connection.execute(begin)
                    let value: Value
                    do throws(ISO_9075.Error) {
                        value = try body(connection)
                    } catch let failure {
                        do {
                            _ = try connection.execute("ROLLBACK")
                        } catch let rollback {
                            throw .transaction("\(failure); ROLLBACK failed (\(rollback)) and \(connection.discard())")
                        }
                        throw failure
                    }
                    _ = try connection.execute(end)
                    return value
                }
            }

            private func leased<Value: Sendable>(
                _ body: @escaping @Sendable (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
            ) async throws(ISO_9075.Error) -> Value {
                let result: Result<Value, ISO_9075.Error>
                do {
                    result = try await client.withConnection { postgres in
                        try await threadPool.runIfActive { [logger] in
                            Result { () throws(ISO_9075.Error) in
                                try body(PostgreSQL.Connection(postgres, logger: logger))
                            }
                        }
                    }
                } catch {
                    throw .connection("\(error)")
                }
                return try result.get()
            }
        }
    }
#endif
