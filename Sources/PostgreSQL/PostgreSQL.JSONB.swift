public import Byte
internal import Foundation
public import ISO_9075_Foundation
public import SQL

extension PostgreSQL {
    public struct JSONB<Value: Codable>: QueryRepresentable {
        public var queryOutput: Value

        public init(queryOutput: Value) {
            self.queryOutput = queryOutput
        }
    }
}

extension PostgreSQL.JSONB: Equatable where Value: Equatable {}

extension PostgreSQL.JSONB: Hashable where Value: Hashable {}

extension PostgreSQL.JSONB: Sendable where Value: Sendable {}

extension PostgreSQL.JSONB: QueryBindable {
    public var queryBinding: ISO_9075.Value {
        do {
            return .json(try Self.encoder.encode(queryOutput).map(Byte.init))
        } catch {
            return .invalid(ISO_9075.Value.Failure(error))
        }
    }
}

extension PostgreSQL.JSONB: QueryDecodable {
    public init(decoder: inout some QueryDecoder) throws(QueryDecodingError) {
        let text = try String(decoder: &decoder)
        do {
            self.init(queryOutput: try Self.decoder.decode(Value.self, from: Data(text.utf8)))
        } catch {
            throw .dataCorrupted("\(text) as JSONB \(Value.self)")
        }
    }
}

extension PostgreSQL.JSONB {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractional))
        }
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let timestamp = try decoder.singleValueContainer().decode(String.self)
            return try Date(timestamp, strategy: timestamp.contains(".") ? fractional : whole)
        }
        return decoder
    }

    private static var fractional: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle().year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: true)
    }

    private static var whole: Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle().year().month().day().dateTimeSeparator(.space).time(includingFractionalSeconds: false)
    }
}
