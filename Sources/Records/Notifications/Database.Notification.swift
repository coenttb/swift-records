import Foundation

extension Database {
    /// A notification message received from PostgreSQL LISTEN/NOTIFY.
    ///
    /// Notifications are sent by PostgreSQL when a NOTIFY command is executed
    /// on a channel that this connection is listening to.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Receive notifications with string payloads
    /// for try await notification in db.notifications(channel: "updates") {
    ///     print("Channel: \(notification.channel)")
    ///     print("Payload: \(notification.payload)")
    /// }
    /// ```
    public struct Notification: Sendable, Hashable {
        /// The channel name on which the notification was sent
        public let channel: String

        /// The notification payload as a string
        public let payload: String

        /// The backend process ID that sent the notification
        public let backendPID: Int32

        public init(channel: String, payload: String, backendPID: Int32) {
            self.channel = channel
            self.payload = payload
            self.backendPID = backendPID
        }
    }
}
