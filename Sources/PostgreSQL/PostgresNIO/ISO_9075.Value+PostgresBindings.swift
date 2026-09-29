#if PostgresNIO
    internal import Byte
    internal import Foundation
    public import ISO_9075_Call_Level_Interface
    public import NIOCore
    public import PostgresNIO
    internal import RFC_4122
    public import Time

    extension PostgresQuery {
        public init(_ rendering: ISO_9075.Rendering) throws(ISO_9075.Error) {
            var bindings = PostgresBindings(capacity: rendering.values.count)
            for value in rendering.values {
                try value.bind(to: &bindings)
            }
            self.init(unsafeSQL: rendering.sql, binds: bindings)
        }
    }

    extension ISO_9075.Value {
        func bind(to bindings: inout PostgresBindings) throws(ISO_9075.Error) {
            switch self {
            case .null: bindings.appendNull()
            case .bool(let bool): bindings.append(bool)
            case .int(let int): bindings.append(int)
            case .double(let double): bindings.append(double)
            case .text(let text): bindings.append(text)
            case .blob(let bytes): bindings.append(ByteBuffer(bytes: bytes.map(\.underlying)))
            case .timestamp(let instant): bindings.append(instant)
            case .uuid(let uuid): bindings.append(Foundation.UUID(uuid: uuid.bytes))
            case .json(let bytes): bindings.append(PostgresData(jsonb: Data(bytes.map(\.underlying))))
            case .decimal(let digits):
                guard digits.wholeMatch(of: /[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?|NaN|[+-]?Infinity/) != nil else {
                    throw .binding(ISO_9075.Value.Failure("\(digits) is not a decimal"))
                }
                bindings.append(PostgresData(type: .numeric, formatCode: .text, value: ByteBuffer(string: digits)))
            case .array(let values, let kind): try ISO_9075.Value.bind(array: values, of: kind, to: &bindings)
            case .invalid(let failure): throw .binding(failure)
            }
        }

        private static func bind(
            array values: [ISO_9075.Value],
            of kind: ISO_9075.Value.Kind,
            to bindings: inout PostgresBindings
        ) throws(ISO_9075.Error) {
            func homogeneous<Element>(_ element: (ISO_9075.Value) -> Element?) throws(ISO_9075.Error) -> [Element] {
                let elements = values.compactMap(element)
                guard elements.count == values.count else {
                    throw .binding(ISO_9075.Value.Failure("PostgreSQL arrays of \(kind) hold only \(kind) elements and no nulls when bound: \(values)"))
                }
                return elements
            }
            switch kind {
            case .bool:
                bindings.append(try homogeneous { if case .bool(let bool) = $0 { bool } else { nil } })
            case .int:
                bindings.append(try homogeneous { if case .int(let int) = $0 { int } else { nil } })
            case .double:
                bindings.append(try homogeneous { if case .double(let double) = $0 { double } else { nil } })
            case .text:
                bindings.append(try homogeneous { if case .text(let text) = $0 { text } else { nil } })
            case .blob:
                bindings.append(try homogeneous { if case .blob(let bytes) = $0 { ByteBuffer(bytes: bytes.map(\.underlying)) } else { nil } })
            case .uuid:
                bindings.append(try homogeneous { if case .uuid(let uuid) = $0 { Foundation.UUID(uuid: uuid.bytes) } else { nil } })
            case .timestamp:
                bindings.append(try homogeneous { if case .timestamp(let instant) = $0 { instant } else { nil } })
            case .decimal, .json:
                throw .binding(ISO_9075.Value.Failure("PostgreSQL has no array binding for \(kind)"))
            }
        }
    }

    extension Time.Instant: @retroactive PostgresNonThrowingEncodable, @retroactive PostgresArrayEncodable {
        public static var psqlType: PostgresDataType { .timestamptz }

        public static var psqlFormat: PostgresFormat { .binary }

        public static var psqlArrayType: PostgresDataType { .timestamptzArray }

        public func encode<JSONEncoder: PostgresJSONEncoder>(
            into byteBuffer: inout ByteBuffer,
            context: PostgresEncodingContext<JSONEncoder>
        ) {
            byteBuffer.writeInteger(
                (secondsSinceUnixEpoch - Time.Instant.postgresEpoch) * 1_000_000 + Int64(nanosecondFraction / 1_000)
            )
        }
    }

    extension Time.Instant: @retroactive PostgresDecodable, @retroactive PostgresArrayDecodable {
        public init<JSONDecoder: PostgresJSONDecoder>(
            from buffer: inout ByteBuffer,
            type: PostgresDataType,
            format: PostgresFormat,
            context: PostgresDecodingContext<JSONDecoder>
        ) throws {
            switch (type, format) {
            case (.timestamptz, .binary), (.timestamp, .binary):
                guard buffer.readableBytes == 8, let microseconds = buffer.readInteger(as: Int64.self) else {
                    throw PostgresDecodingError.Code.failure
                }
                let (seconds, remainder) = microseconds.quotientAndRemainder(dividingBy: 1_000_000)
                self.init(
                    _unchecked: (),
                    secondsSinceUnixEpoch: Time.Instant.postgresEpoch + seconds - (remainder < 0 ? 1 : 0),
                    nanosecondFraction: Int32((remainder < 0 ? remainder + 1_000_000 : remainder) * 1_000)
                )
            case (.date, .binary):
                guard buffer.readableBytes == 4, let days = buffer.readInteger(as: Int32.self) else {
                    throw PostgresDecodingError.Code.failure
                }
                self.init(secondsSinceUnixEpoch: Time.Instant.postgresEpoch + Int64(days) * 86_400)
            default:
                throw PostgresDecodingError.Code.typeMismatch
            }
        }

        static let postgresEpoch: Int64 = 946_684_800
    }
#endif
