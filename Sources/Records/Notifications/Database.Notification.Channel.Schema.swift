import Foundation

extension Database.Notification {
    /// A protocol that couples a notification channel name with its payload type.
    ///
    /// Implement this protocol to create type-safe notification channels with compile-time guarantees
    /// about the payload structure. While the protocol is named `Channel.Schema` for conceptual clarity,
    /// it must be declared directly on `Database.Notification` due to Swift's restrictions on protocols
    /// in generic contexts.
    ///
    /// ```swift
    /// struct UserEventsChannel: Database.Notification.ChannelSchema {
    ///     static let channelName = "user_events"
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let userID: Int
    ///         let action: String
    ///         let timestamp: Date
    ///     }
    /// }
    ///
    /// // Type-safe listening
    /// for try await notification in try await db.notifications(schema: UserEventsChannel.self) {
    ///     print("User \(notification.payload.userID) performed: \(notification.payload.action)")
    /// }
    ///
    /// // Type-safe sending
    /// try await db.notify(
    ///     schema: UserEventsChannel.self,
    ///     payload: UserEventsChannel.Payload(userID: 123, action: "login", timestamp: Date())
    /// )
    /// ```
    public protocol ChannelSchema {
        /// The payload type that will be sent and received on this channel.
        /// Must be Codable for automatic JSON encoding/decoding and Sendable for Swift concurrency.
        associatedtype Payload: Codable & Sendable

        /// The PostgreSQL channel name.
        /// Must be a valid PostgreSQL identifier (lowercase, alphanumeric, underscores).
        static var channelName: String { get }
    }
}

extension Database.Notification.ChannelSchema {
    /// A type-safe channel instance for this schema.
    ///
    /// Use this to get a phantom-typed channel from your schema:
    ///
    /// ```swift
    /// let channel = UserEventsChannel.channel
    /// for try await notification in try await db.notifications(channel: channel) {
    ///     // notification.payload is already decoded as UserEventsChannel.Payload
    /// }
    /// ```
    @inlinable
    public static var channel: Database.Notification.Channel<Payload> {
        Database.Notification.Channel(channelName)
    }
}
