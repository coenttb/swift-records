#if PostgresNIO
    internal import Foundation
    public import ISO_9075_Call_Level_Interface
    internal import NIOCore
    public import PostgresNIO
    internal import RFC_4122
    internal import Time

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
            case .timestamp(let instant): bindings.append(Date(instant))
            case .uuid(let uuid): bindings.append(Foundation.UUID(uuid: uuid.bytes))
            case .json(let bytes): bindings.append(PostgresData(jsonb: Data(bytes.map(\.underlying))))
            case .decimal(let digits):
                guard let decimal = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else {
                    throw .binding(ISO_9075.Value.Failure("\(digits) is not a decimal"))
                }
                do {
                    try bindings.append(decimal)
                } catch {
                    throw .binding(ISO_9075.Value.Failure(error))
                }
            case .array(let values): try ISO_9075.Value.bind(array: values, to: &bindings)
            case .invalid(let failure): throw .binding(failure)
            }
        }

        private static func bind(array values: [ISO_9075.Value], to bindings: inout PostgresBindings) throws(ISO_9075.Error) {
            func homogeneous<Element>(_ element: (ISO_9075.Value) -> Element?) throws(ISO_9075.Error) -> [Element] {
                let elements = values.compactMap(element)
                guard elements.count == values.count else {
                    throw .binding(ISO_9075.Value.Failure("PostgreSQL arrays hold one element type and no nulls when bound: \(values)"))
                }
                return elements
            }
            switch values.first {
            case nil:
                bindings.append([String]())
            case .bool:
                bindings.append(try homogeneous { if case .bool(let bool) = $0 { bool } else { nil } })
            case .int:
                bindings.append(try homogeneous { if case .int(let int) = $0 { int } else { nil } })
            case .double:
                bindings.append(try homogeneous { if case .double(let double) = $0 { double } else { nil } })
            case .text:
                bindings.append(try homogeneous { if case .text(let text) = $0 { text } else { nil } })
            case .uuid:
                bindings.append(try homogeneous { if case .uuid(let uuid) = $0 { Foundation.UUID(uuid: uuid.bytes) } else { nil } })
            case .timestamp:
                bindings.append(try homogeneous { if case .timestamp(let instant) = $0 { Date(instant) } else { nil } })
            case let first?:
                throw .binding(ISO_9075.Value.Failure("PostgreSQL has no array binding for \(first)"))
            }
        }
    }

    extension Date {
        init(_ instant: Time.Instant) {
            self.init(
                timeIntervalSince1970: Double(instant.secondsSinceUnixEpoch)
                    + Double(instant.nanosecondFraction) / 1_000_000_000
            )
        }
    }

    extension Time.Instant {
        init(_ date: Date) {
            let seconds = date.timeIntervalSince1970.rounded(.down)
            self.init(
                _unchecked: (),
                secondsSinceUnixEpoch: Int64(seconds),
                nanosecondFraction: Int32(((date.timeIntervalSince1970 - seconds) * 1_000_000_000).rounded(.down))
            )
        }
    }
#endif
