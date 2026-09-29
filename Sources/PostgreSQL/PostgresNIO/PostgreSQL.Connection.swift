#if PostgresNIO
    public import ISO_9075_Call_Level_Interface
    public import Logging
    internal import NIOCore
    public import PostgresNIO
    internal import Synchronization

    extension PostgreSQL {
        public struct Connection: ISO_9075.Connection, Sendable {
            public let dialect = PostgreSQL()
            public let postgres: PostgresConnection
            public let logger: Logger

            public init(_ postgres: PostgresConnection, logger: Logger) {
                self.postgres = postgres
                self.logger = logger
            }

            public func execute(_ statement: ISO_9075.Rendering) throws(ISO_9075.Error) -> Int {
                statement.sql.isEmpty ? 0 : try result(statement).metadata.rows ?? 0
            }

            public func fetchAll<Value>(
                _ statement: ISO_9075.Rendering,
                decode: (PostgreSQL.Row) throws(ISO_9075.Error) -> Value
            ) throws(ISO_9075.Error) -> [Value] {
                statement.sql.isEmpty
                    ? []
                    : try result(statement).rows.map { row throws(ISO_9075.Error) in try decode(PostgreSQL.Row(row)) }
            }

            func discard() -> String {
                do {
                    try postgres.close().wait()
                    return "the connection was closed"
                } catch {
                    return "closing the connection failed: \(error)"
                }
            }

            func result(_ statement: ISO_9075.Rendering) throws(ISO_9075.Error) -> PostgresQueryResult {
                let query = try PostgresQuery(statement)
                do {
                    return try postgres.query(query, logger: logger).wait()
                } catch {
                    throw .execution("\(String(reflecting: error)) in \(statement.sql)")
                }
            }
        }
    }

    extension PostgreSQL.Connection {
        public func withSavepoint<Value>(
            _ name: String,
            _ body: (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
        ) throws(ISO_9075.Error) -> Value {
            let savepoint = ISO_9075.Identifier(name)
            _ = try execute("SAVEPOINT \(savepoint)")
            do {
                let value = try body(self)
                _ = try execute("RELEASE SAVEPOINT \(savepoint)")
                return value
            } catch {
                do {
                    _ = try execute("ROLLBACK TO SAVEPOINT \(savepoint)")
                } catch let rollback {
                    throw .transaction("\(error); rolling back to savepoint \(name) failed: \(rollback)")
                }
                throw error
            }
        }

        public func withSavepoint<Value>(
            _ body: (PostgreSQL.Connection) throws(ISO_9075.Error) -> Value
        ) throws(ISO_9075.Error) -> Value {
            try withSavepoint("savepoint_\(PostgreSQL.Connection.names.add(1, ordering: .relaxed).newValue)", body)
        }

        static let names = Atomic<Int>(0)
    }
#endif
