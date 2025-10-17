import Foundation
import PostgresNIO
import Tagged

extension Database {
    /// Internal stream of raw notifications from PostgreSQL LISTEN/NOTIFY.
    ///
    /// This type is used internally to feed the public `NotificationStream<Payload>`.
    /// Users should use the typed notification APIs instead.
    ///
    /// This is a simple typealias because AsyncThrowingStream handles cleanup automatically
    /// via its `onTermination` callback - no manual lifecycle management needed.
    typealias RawNotificationStream = AsyncThrowingStream<Notification, any Swift.Error>

    /// A stream of typed notifications with automatic JSON decoding.
    ///
    /// This is the **default** notification stream type. It automatically decodes
    /// notification payloads from JSON into the specified Codable type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderChange: Codable {
    ///     let id: Int
    ///     let action: String
    /// }
    ///
    /// let stream: Database.NotificationStream<ReminderChange>
    ///     = try await db.notifications(channel: "reminders")
    ///
    /// for try await change in stream {
    ///     print("Reminder \(change.id) was \(change.action)")
    /// }
    /// ```
    ///
    /// If you need access to notification metadata (channel, backendPID), use
    /// `notificationEvents()` instead to get `NotificationEvent<Payload>` with full context.
    public struct NotificationStream<Payload: Decodable & Sendable>: AsyncSequence, Sendable {
        public typealias Element = Payload

        private let base: AsyncThrowingStream<Notification, any Swift.Error>
        private let decoder: JSONDecoder

        init(base: AsyncThrowingStream<Notification, any Swift.Error>, decoder: JSONDecoder = JSONDecoder()) {
            self.base = base
            self.decoder = decoder
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(base: base.makeAsyncIterator(), decoder: decoder)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator
            private let decoder: JSONDecoder

            init(base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator, decoder: JSONDecoder) {
                self.base = base
                self.decoder = decoder
            }

            public mutating func next() async throws -> Payload? {
                guard let notification = try await base.next() else {
                    return nil
                }

                guard let data = notification.payload.data(using: .utf8) else {
                    throw Database.Error.invalidNotificationPayload(
                        "Payload is not valid UTF-8: \(notification.payload)"
                    )
                }

                do {
                    return try decoder.decode(Payload.self, from: data)
                } catch {
                    throw Database.Error.notificationDecodingFailed(
                        type: String(describing: Payload.self),
                        payload: notification.payload,
                        underlying: error
                    )
                }
            }
        }
    }

    /// A stream of notification events with full metadata (payload + channel + backendPID).
    ///
    /// This stream type provides access to both the decoded payload and notification metadata.
    /// Use this when you need to know which channel or backend sent the notification.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct UserAction: Codable {
    ///     let userID: Int
    ///     let action: String
    /// }
    ///
    /// let stream = try await db.notificationEvents(on: channel, expecting: UserAction.self)
    ///
    /// for try await event in stream {
    ///     print("User \(event.payload.userID) did \(event.payload.action)")
    ///     print("From backend: \(event.backendPID)")
    /// }
    /// ```
    public struct NotificationEventStream<Payload: Decodable & Sendable>: AsyncSequence, Sendable {
        public typealias Element = NotificationEvent<Payload>

        private let base: AsyncThrowingStream<Notification, any Swift.Error>
        private let decoder: JSONDecoder

        init(base: AsyncThrowingStream<Notification, any Swift.Error>, decoder: JSONDecoder = JSONDecoder()) {
            self.base = base
            self.decoder = decoder
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(base: base.makeAsyncIterator(), decoder: decoder)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator
            private let decoder: JSONDecoder

            init(base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator, decoder: JSONDecoder) {
                self.base = base
                self.decoder = decoder
            }

            public mutating func next() async throws -> NotificationEvent<Payload>? {
                guard let notification = try await base.next() else {
                    return nil
                }

                guard let data = notification.payload.data(using: .utf8) else {
                    throw Database.Error.invalidNotificationPayload(
                        "Payload is not valid UTF-8: \(notification.payload)"
                    )
                }

                do {
                    let payload = try decoder.decode(Payload.self, from: data)
                    return NotificationEvent(
                        payload: payload,
                        channel: notification.channel,
                        backendPID: notification.backendPID
                    )
                } catch {
                    throw Database.Error.notificationDecodingFailed(
                        type: String(describing: Payload.self),
                        payload: notification.payload,
                        underlying: error
                    )
                }
            }
        }
    }
}

// MARK: - Reader Extension

extension Database.Reader {
    /// Listens for typed notifications with automatic JSON decoding.
    ///
    /// This method returns immediately with a stream. The PostgreSQL LISTEN command
    /// executes asynchronously in the background. Use `for await _ in ready { break }`
    /// to wait until listening is active before sending notifications.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderChange: Codable {
    ///     let id: Int
    ///     let action: String
    ///     let title: String
    /// }
    ///
    /// let (stream, ready) = try await db.notifications(on: channel, expecting: ReminderChange.self)
    ///
    /// Task {
    ///     for try await change in stream {
    ///         print("Reminder \(change.id): \(change.action) - \(change.title)")
    ///     }
    /// }
    ///
    /// // Wait for LISTEN to complete
    /// for await _ in ready { break }
    ///
    /// // Now safe to send
    /// try await db.notify(channel: channel, payload: myChange)
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name to listen on
    ///   - type: The Codable type to decode payloads into (can be inferred from context)
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notifications<Payload: Decodable & Sendable>(
        on channel: ChannelName,
        expecting type: Payload.Type = Payload.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationStream<Payload>, ready: AsyncStream<Void>) {
        try await _notifications(channel: channel.rawValue, decoder: decoder)
    }

    // MARK: - Type-Safe Channel API

    /// Listens for typed notifications on a type-safe channel.
    ///
    /// This method provides compile-time type safety by coupling the channel name
    /// with its payload type. The returned stream automatically decodes JSON payloads.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct UserEvent: Codable, Sendable {
    ///     let userID: Int
    ///     let action: String
    /// }
    ///
    /// let channel: Database.Notification.Channel<UserEvent> = "user_events"
    /// let (stream, ready) = try await db.notifications(on: channel)
    ///
    /// Task {
    ///     for try await event in stream {
    ///         print("User \(event.userID) performed: \(event.action)")
    ///     }
    /// }
    ///
    /// for await _ in ready { break }
    /// ```
    ///
    /// - Parameters:
    ///   - channel: A type-safe channel that couples the name with the payload type
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notifications<Payload>(
        on channel: Database.Notification.Channel<Payload>,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationStream<Payload>, ready: AsyncStream<Void>) {
        try await notifications(on: channel.name, expecting: Payload.self, decoder: decoder)
    }

    /// Listens for notifications using a notification channel schema.
    ///
    /// This method provides compile-time type safety through a schema that defines
    /// both the channel name and payload type in one place.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct UserEventsChannel: NotificationChannelSchema {
    ///     static let channelName = "user_events"
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let userID: Int
    ///         let action: String
    ///     }
    /// }
    ///
    /// let (stream, ready) = try await db.notifications(from: UserEventsChannel.self)
    ///
    /// Task {
    ///     for try await event in stream {
    ///         print("User \(event.userID) performed: \(event.action)")
    ///     }
    /// }
    ///
    /// for await _ in ready { break }
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notifications<Schema: Database.Notification.ChannelSchema>(
        from schema: Schema.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationStream<Schema.Payload>, ready: AsyncStream<Void>) {
        try await notifications(on: Schema.channelName, expecting: Schema.Payload.self, decoder: decoder)
    }

    // MARK: - Notification Events API (with metadata)

    /// Listens for notification events with full metadata (payload + channel + backendPID).
    ///
    /// This method is similar to `notifications()` but returns `NotificationEvent<Payload>`
    /// instead of just `Payload`, giving you access to the channel name and backend process ID.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderChange: Codable {
    ///     let id: Int
    ///     let action: String
    /// }
    ///
    /// let (stream, ready) = try await db.notificationEvents(on: channel, expecting: ReminderChange.self)
    ///
    /// Task {
    ///     for try await event in stream {
    ///         print("Change: \(event.payload)")
    ///         print("Channel: \(event.channel)")
    ///         print("Backend PID: \(event.backendPID)")
    ///     }
    /// }
    ///
    /// for await _ in ready { break }
    /// try await db.notify(channel: channel, payload: myChange)
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name to listen on
    ///   - type: The Codable type to decode payloads into (can be inferred from context)
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification event stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notificationEvents<Payload: Decodable & Sendable>(
        on channel: ChannelName,
        expecting type: Payload.Type = Payload.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationEventStream<Payload>, ready: AsyncStream<Void>) {
        try await _notificationEvents(channel: channel.rawValue, decoder: decoder)
    }

    /// Listens for notification events on a type-safe channel.
    ///
    /// - Parameters:
    ///   - channel: A type-safe channel that couples the name with the payload type
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification event stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notificationEvents<Payload>(
        on channel: Database.Notification.Channel<Payload>,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationEventStream<Payload>, ready: AsyncStream<Void>) {
        try await notificationEvents(on: channel.name, expecting: Payload.self, decoder: decoder)
    }

    /// Listens for notification events using a notification channel schema.
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: A tuple of (notification event stream, readiness signal)
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notificationEvents<Schema: Database.Notification.ChannelSchema>(
        from schema: Schema.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> (stream: Database.NotificationEventStream<Schema.Payload>, ready: AsyncStream<Void>) {
        try await notificationEvents(on: Schema.channelName, expecting: Schema.Payload.self, decoder: decoder)
    }

    /// Internal implementation with readiness signaling.
    ///
    /// This reuses the primitive `_rawNotifications()` and wraps it with
    /// `NotificationStream` to decode just the payload.
    private func _notifications<Payload: Decodable & Sendable>(
        channel: String,
        decoder: JSONDecoder
    ) async throws -> (stream: Database.NotificationStream<Payload>, ready: AsyncStream<Void>) {

        // Get the raw notification stream (primitive)
        let (rawStream, ready) = try await _rawNotifications(channel: channel)

        // Wrap with NotificationStream (composition)
        let typedStream = Database.NotificationStream<Payload>(base: rawStream, decoder: decoder)

        return (typedStream, ready)
    }

    /// Internal implementation for notification events with full metadata.
    ///
    /// This reuses the primitive `_rawNotifications()` and wraps it with
    /// `NotificationEventStream` to expose metadata alongside decoded payload.
    private func _notificationEvents<Payload: Decodable & Sendable>(
        channel: String,
        decoder: JSONDecoder
    ) async throws -> (stream: Database.NotificationEventStream<Payload>, ready: AsyncStream<Void>) {

        // Get the raw notification stream (primitive)
        let (rawStream, ready) = try await _rawNotifications(channel: channel)

        // Wrap with NotificationEventStream (composition)
        let eventStream = Database.NotificationEventStream<Payload>(
            base: rawStream,
            decoder: decoder
        )

        return (eventStream, ready)
    }

    /// Primitive: raw notification stream without decoding.
    ///
    /// This is the foundational implementation that both `NotificationStream`
    /// and `NotificationEventStream` compose upon.
    private func _rawNotifications(
        channel: String
    ) async throws -> (stream: AsyncThrowingStream<Database.Notification, any Swift.Error>, ready: AsyncStream<Void>) {

        // Try to resolve a client from the database connection
        let useClient: PostgresClient

        if let directClient = self as? PostgresClient {
            // Direct PostgresClient - use it
            useClient = directClient
        } else if let capable = self as? NotificationCapable,
                  let postgresClient = try await capable.postgresClient {
            // Wrapped client (Database.Reader wrapping PostgresClient) - use it
            useClient = postgresClient
        } else {
            throw Database.Error.notificationNotSupported(
                "This database type does not support notifications. " +
                "Notifications require a PostgresClient connection."
            )
        }

        // Create readiness signal channel
        let (readyStream, readyContinuation) = AsyncStream.makeStream(of: Void.self)

        // Create the notification stream with structured concurrency and bounded buffer
        // Buffering strategy: keep newest 100 notifications, drop oldest on overflow
        // This prevents memory exhaustion if notifications arrive faster than consumption
        let notificationStream = AsyncThrowingStream<Database.Notification, any Swift.Error>(
            bufferingPolicy: .bufferingNewest(100)
        ) { continuation in
            // This task is tied to the stream's lifetime via onTermination
            let listenerTask = Task {
                do {
                    try await useClient.withConnection { postgres in
                        // Set up notification handler FIRST (before LISTEN)
                        let listenerContext = postgres.addListener(channel: channel) { _, notification in
                            // Convert PostgresNIO notification to our typed notification
                            do {
                                let dbNotification = try Database.Notification(
                                    rawChannel: notification.channel,
                                    payload: notification.payload,
                                    backendPID: notification.backendPID
                                )
                                continuation.yield(dbNotification)
                            } catch {
                                // Invalid channel name from PostgreSQL (shouldn't happen)
                                continuation.finish(throwing: error)
                            }
                        }

                        // Execute LISTEN command
                        let connection = Database.Connection(postgres)
                        let channelName = try ChannelName(validating: channel)
                        try await connection.execute("LISTEN \(channelName.quoted)")

                        // ✅ LISTEN complete - signal readiness!
                        readyContinuation.yield(())
                        readyContinuation.finish()

                        // Keep the connection alive indefinitely until cancelled
                        // This will be cancelled when the stream consumer stops iterating
                        try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Error>) in
                            // Never resume - only cancelled via task cancellation
                        }

                        // If we reach here (task was cancelled), clean up
                        listenerContext.stop()

                        do {
                            try await connection.execute("UNLISTEN \(channelName.quoted)")
                        } catch {
                            // Log cleanup errors - don't swallow them
                            print("⚠️ Failed to UNLISTEN channel '\(channel)': \(error)")
                        }

                        continuation.finish()
                    }
                } catch {
                    // If LISTEN fails, signal error on readiness too
                    readyContinuation.finish()
                    continuation.finish(throwing: error)
                }
            }

            // Cleanup happens automatically when stream consumer stops iterating
            continuation.onTermination = { @Sendable _ in
                listenerTask.cancel()
            }
        }

        return (notificationStream, readyStream)
    }
}

// MARK: - Writer Extension

extension Database.Writer {
    /// Sends a notification to a PostgreSQL channel.
    ///
    /// This method executes PostgreSQL's NOTIFY command to send a message to
    /// all connections currently listening on the specified channel.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Send a simple string notification
    /// let channel = try ChannelName(validating: "updates")
    /// try await db.notify(channel: channel, payload: "New data available")
    /// ```
    ///
    /// ## Within a Transaction
    ///
    /// ```swift
    /// try await db.write { db in
    ///     // Insert record
    ///     try await Record.insert { ... }.execute(db)
    ///
    ///     // Notify listeners
    ///     let channel = try ChannelName(validating: "records")
    ///     try await db.notify(channel: channel, payload: "Record created")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name
    ///   - payload: The notification payload (must be a valid PostgreSQL string literal)
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(
        channel: ChannelName,
        payload: String
    ) async throws {
        try await write { db in
            // Escape single quotes in payload for SQL safety
            let escapedPayload = payload.replacingOccurrences(of: "'", with: "''")
            try await db.execute("NOTIFY \(channel.quoted), '\(escapedPayload)'")
        }
    }

    /// Sends a typed notification with automatic JSON encoding.
    ///
    /// This method encodes a Codable value to JSON and sends it as a notification
    /// payload. This is the recommended way to send structured data.
    ///
    /// **PostgreSQL Limit**: NOTIFY payloads have a maximum size of 8000 bytes.
    /// This method validates payload size and throws a helpful error if exceeded.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderChange: Codable {
    ///     let id: Int
    ///     let action: String
    ///     let title: String
    /// }
    ///
    /// try await db.notify(
    ///     channel: ChannelName(validating: "reminders"),
    ///     payload: ReminderChange(id: 123, action: "updated", title: "Buy milk")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name
    ///   - payload: The Codable value to encode and send
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors, encoding errors, or `notificationPayloadTooLarge` if payload exceeds 8000 bytes
    public func notify<Payload: Encodable & Sendable>(
        channel: ChannelName,
        payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw Database.Error.invalidNotificationPayload(
                "Failed to encode payload to UTF-8 JSON string"
            )
        }

        // PostgreSQL NOTIFY has an 8000 byte limit on payloads
        let maxPayloadSize = 8000
        let payloadSize = json.utf8.count

        guard payloadSize <= maxPayloadSize else {
            throw Database.Error.notificationPayloadTooLarge(
                size: payloadSize,
                limit: maxPayloadSize,
                hint: "Consider using a reference ID (e.g., record ID) and fetching full data from the database instead of sending large payloads"
            )
        }

        try await notify(channel: channel, payload: json)
    }

    /// Sends a notification without a payload.
    ///
    /// This is useful for simple event notifications where the channel name
    /// itself conveys all necessary information.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let channel = try ChannelName(validating: "cache_invalidate")
    /// try await db.notify(channel: channel)
    /// ```
    ///
    /// - Parameter channel: The type-safe PostgreSQL channel name
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(channel: ChannelName) async throws {
        try await write { db in
            try await db.execute("NOTIFY \(channel.quoted)")
        }
    }

    // MARK: - Type-Safe Channel API

    /// Sends a typed notification on a type-safe channel.
    ///
    /// This method provides compile-time type safety by ensuring the payload type
    /// matches the channel's expected type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct UserEvent: Codable, Sendable {
    ///     let userID: Int
    ///     let action: String
    /// }
    ///
    /// let channel: Database.Notification.Channel<UserEvent> = "user_events"
    ///
    /// try await db.notify(
    ///     channel: channel,
    ///     payload: UserEvent(userID: 123, action: "login")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - channel: A type-safe channel that couples the name with the payload type
    ///   - payload: The Codable value to encode and send
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors or encoding errors
    public func notify<Payload>(
        channel: Database.Notification.Channel<Payload>,
        payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        try await notify(channel: channel.name, payload: payload, encoder: encoder)
    }

    /// Sends a notification using a notification channel schema.
    ///
    /// This method provides compile-time type safety through a schema that defines
    /// both the channel name and payload type in one place.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct UserEventsChannel: NotificationChannelSchema {
    ///     static let channelName = "user_events"
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let userID: Int
    ///         let action: String
    ///     }
    /// }
    ///
    /// try await db.notify(
    ///     schema: UserEventsChannel.self,
    ///     payload: UserEventsChannel.Payload(userID: 123, action: "login")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - payload: The payload value matching the schema's Payload type
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors or encoding errors
    public func notify<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type,
        payload: Schema.Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        try await notify(channel: Schema.channelName, payload: payload, encoder: encoder)
    }

    /// Sends a notification without a payload on a type-safe channel.
    ///
    /// This is useful for simple event notifications where the channel name
    /// itself conveys all necessary information.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let channel: Database.Notification.Channel<Void> = "cache_invalidate"
    /// try await db.notify(channel: channel)
    /// ```
    ///
    /// - Parameter channel: A type-safe channel (typically with Void payload type)
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify<Payload>(
        channel: Database.Notification.Channel<Payload>
    ) async throws {
        try await notify(channel: channel.name)
    }
}

// MARK: - Connection.Protocol Extension

extension Database.Connection.`Protocol` {
    /// Sends a notification to a PostgreSQL channel from within a transaction.
    ///
    /// This method is available on database connections within `write` blocks.
    /// The notification will only be sent if the transaction commits successfully.
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name
    ///   - payload: The notification payload
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(
        channel: ChannelName,
        payload: String
    ) async throws {
        let escapedPayload = payload.replacingOccurrences(of: "'", with: "''")
        try await execute("NOTIFY \(channel.quoted), '\(escapedPayload)'")
    }

    /// Sends a typed notification with automatic JSON encoding from within a transaction.
    ///
    /// **PostgreSQL Limit**: NOTIFY payloads have a maximum size of 8000 bytes.
    ///
    /// - Parameters:
    ///   - channel: The type-safe PostgreSQL channel name
    ///   - payload: The Codable value to encode and send
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors, encoding errors, or `notificationPayloadTooLarge` if payload exceeds 8000 bytes
    public func notify<Payload: Encodable & Sendable>(
        channel: ChannelName,
        payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw Database.Error.invalidNotificationPayload(
                "Failed to encode payload to UTF-8 JSON string"
            )
        }

        // PostgreSQL NOTIFY has an 8000 byte limit on payloads
        let maxPayloadSize = 8000
        let payloadSize = json.utf8.count

        guard payloadSize <= maxPayloadSize else {
            throw Database.Error.notificationPayloadTooLarge(
                size: payloadSize,
                limit: maxPayloadSize,
                hint: "Consider using a reference ID and fetching full data from the database"
            )
        }

        try await notify(channel: channel, payload: json)
    }

    /// Sends a notification without a payload from within a transaction.
    ///
    /// - Parameter channel: The type-safe PostgreSQL channel name
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(channel: ChannelName) async throws {
        try await execute("NOTIFY \(channel.quoted)")
    }

    // MARK: - Type-Safe Channel API

    /// Sends a typed notification on a type-safe channel from within a transaction.
    ///
    /// - Parameters:
    ///   - channel: A type-safe channel that couples the name with the payload type
    ///   - payload: The Codable value to encode and send
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors or encoding errors
    public func notify<Payload>(
        channel: Database.Notification.Channel<Payload>,
        payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        try await notify(channel: channel.name, payload: payload, encoder: encoder)
    }

    /// Sends a notification using a notification channel schema from within a transaction.
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - payload: The payload value matching the schema's Payload type
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors or encoding errors
    public func notify<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type,
        payload: Schema.Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        try await notify(channel: Schema.channelName, payload: payload, encoder: encoder)
    }

    /// Sends a notification without a payload on a type-safe channel from within a transaction.
    ///
    /// - Parameter channel: A type-safe channel
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify<Payload>(
        channel: Database.Notification.Channel<Payload>
    ) async throws {
        try await notify(channel: channel.name)
    }
}
