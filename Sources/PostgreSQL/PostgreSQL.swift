internal import Byte
public import ISO_9075_Foundation

public struct PostgreSQL: ISO_9075.Dialect {
    public init() {}

    public func placeholder(_ offset: Int) -> String { "$\(offset)" }

    public func literal(_ value: ISO_9075.Value) throws(ISO_9075.Value.Failure) -> String {
        switch value {
        case .timestamp(let instant):
            "TIMESTAMPTZ " + ISO_9075.Literal.character(try ISO_9075.Literal.timestamp(instant) + "+00")
        case .blob(let bytes):
            ISO_9075.Literal.character("\\x" + bytes.map { byte in
                let hex = String(byte.bitPattern, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }.joined()) + "::BYTEA"
        case .array(let values):
            "ARRAY[" + (try values.map { value throws(ISO_9075.Value.Failure) in try literal(value) }).joined(separator: ", ") + "]"
        default:
            try value.literal
        }
    }
}
