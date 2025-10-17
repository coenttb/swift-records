import Foundation

extension Database.Notification {
    /// A phantom-typed notification channel that couples a channel name with its payload type.
    ///
    /// This type provides compile-time type safety for notification payloads without runtime overhead.
    /// The payload type parameter `Payload` is phantom - it exists only at compile time to ensure
    /// type safety when sending and receiving notifications.
    ///
    /// You can create channels in three ways:
    ///
    /// 1. From a `Database.Notification.Channel.Schema`:
    /// ```swift
    /// let channel = UserEventsChannel.channel
    /// ```
    ///
    /// 2. Using a string literal:
    /// ```swift
    /// let channel: Database.Notification.Channel<MyPayload> = "my_channel"
    /// ```
    ///
    /// 3. Explicitly:
    /// ```swift
    /// let channel = Database.Notification.Channel<MyPayload>("my_channel")
    /// ```
    public struct Channel<Payload: Codable & Sendable>: Sendable, Hashable, ExpressibleByStringLiteral {
        /// The PostgreSQL channel name.
        public let name: String

        /// Creates a type-safe notification channel.
        ///
        /// - Parameter name: The PostgreSQL channel name. Should be a valid PostgreSQL identifier.
        @inlinable
        public init(_ name: String) {
            self.name = name
        }

        /// Creates a type-safe notification channel from a string literal.
        ///
        /// This allows you to write:
        /// ```swift
        /// let channel: Database.Notification.Channel<MyPayload> = "my_channel"
        /// ```
        @inlinable
        public init(stringLiteral value: String) {
            self.name = value
        }
    }
}
