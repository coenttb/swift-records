import Foundation
import NIOCore
import PostgresNIO
import StructuredQueriesPostgres

extension PostgresQuery {
    package init(from fragment: QueryFragment) {
        var parameterIndex = 0
        var bindings = PostgresBindings()
        var sqlParts: [String] = []

        // Process segments to build SQL and bindings
        for segment in fragment.segments {
            switch segment {
            case .sql(let sql):
                sqlParts.append(sql)
            case .binding(let binding):
                parameterIndex += 1
                sqlParts.append("$\(parameterIndex)")
                fragment.appendBinding(binding, to: &bindings)
            }
        }

        // Join the SQL parts and normalize whitespace
        let sql = sqlParts.joined()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")

        self = PostgresQuery(unsafeSQL: sql, binds: bindings)
    }
}

extension QueryFragment {
    /// Converts a QueryFragment to a PostgresQuery for execution
    package func toPostgresQuery() -> PostgresQuery { .init(from: self) }

    func appendBinding(_ binding: QueryBinding, to bindings: inout PostgresBindings) {
        switch binding {
        case .null:
            bindings.appendNull()
        case .int(let value):
            bindings.append(Int(value), context: .default)
        case .double(let value):
            bindings.append(value, context: .default)
        case .text(let value):
            bindings.append(value, context: .default)
        case .blob(let bytes):
            // Convert [UInt8] to ByteBuffer for PostgreSQL bytea type
            var buffer = ByteBufferAllocator().buffer(capacity: bytes.count)
            buffer.writeBytes(bytes)
            bindings.append(buffer, context: .default)
        case .date(let date):
            bindings.append(date, context: .default)
        case .uuid(let uuid):
            bindings.append(uuid, context: .default)
        case .invalid(let error):
            // Log error and append null as fallback
            print("Warning: Invalid binding with error: \(error)")
            bindings.appendNull()
        case .bool(let value):
            // Use native PostgreSQL boolean type
            bindings.append(value, context: .default)
        case .jsonb(let data):
            // Use PostgresNIO's JSONB support
            let postgresData = PostgresData(jsonb: data)
            bindings.append(postgresData)
        case .decimal(let value):
            // Use PostgresNIO's Decimal support for NUMERIC type
            do {
                try bindings.append(value, context: .default)
            } catch {
                // Decimal encoding should never fail in practice, but handle the error
                // by appending null as a fallback (similar to .invalid case)
                print("Warning: Failed to encode Decimal value: \(error)")
                bindings.appendNull()
            }
        }
    }
}
