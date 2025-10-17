import Foundation
import PostgresNIO

extension Database {
    /// A stream of notifications from PostgreSQL LISTEN/NOTIFY.
    ///
    /// This type wraps an AsyncSequence that yields notifications as they arrive
    /// from PostgreSQL. The stream remains active until cancelled or until an
    /// error occurs.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stream = try await db.notifications(channel: "updates")
    ///
    /// for try await notification in stream {
    ///     print("Received: \(notification.payload)")
    /// }
    /// ```
    public struct NotificationStream: AsyncSequence, Sendable {
        public typealias Element = Notification

        // The type of error this sequence can throw - uses Swift.Error protocol
        public typealias Failure = any Swift.Error

        private let _makeIterator: @Sendable () -> AsyncIterator

        init(
            stream: AsyncThrowingStream<Notification, any Swift.Error>,
            cleanup: @escaping @Sendable () async -> Void
        ) {
            self._makeIterator = {
                AsyncIterator(
                    base: stream.makeAsyncIterator(),
                    cleanup: cleanup
                )
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            _makeIterator()
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator
            private let cleanup: @Sendable () async -> Void
            private var didCleanup = false

            init(
                base: AsyncThrowingStream<Notification, any Swift.Error>.AsyncIterator,
                cleanup: @escaping @Sendable () async -> Void
            ) {
                self.base = base
                self.cleanup = cleanup
            }

            public mutating func next() async throws -> Notification? {
                do {
                    if let notification = try await base.next() {
                        return notification
                    } else {
                        // Stream ended naturally
                        await performCleanup()
                        return nil
                    }
                } catch {
                    // Error occurred, cleanup and rethrow
                    await performCleanup()
                    throw error
                }
            }

            private mutating func performCleanup() async {
                guard !didCleanup else { return }
                didCleanup = true
                await cleanup()
            }
        }
    }

    /// A stream of typed notifications with automatic JSON decoding.
    ///
    /// This type automatically decodes notification payloads from JSON into
    /// the specified Decodable type.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct ReminderChange: Codable {
    ///     let id: Int
    ///     let action: String
    /// }
    ///
    /// let stream: Database.TypedNotificationStream<ReminderChange>
    ///     = try await db.notifications(channel: "reminders")
    ///
    /// for try await change in stream {
    ///     print("Reminder \(change.id) was \(change.action)")
    /// }
    /// ```
    public struct TypedNotificationStream<Payload: Decodable & Sendable>: AsyncSequence, Sendable {
        public typealias Element = Payload

        private let base: NotificationStream
        private let decoder: JSONDecoder

        init(base: NotificationStream, decoder: JSONDecoder = JSONDecoder()) {
            self.base = base
            self.decoder = decoder
        }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(base: base.makeAsyncIterator(), decoder: decoder)
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            private var base: NotificationStream.AsyncIterator
            private let decoder: JSONDecoder

            init(base: NotificationStream.AsyncIterator, decoder: JSONDecoder) {
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
}

// MARK: - Reader Extension

extension Database.Reader {
    /// Listens for notifications on a specific PostgreSQL channel.
    ///
    /// This method subscribes to notifications on the specified channel and returns
    /// an AsyncSequence that yields notifications as they arrive. The subscription
    /// remains active until the sequence is cancelled or an error occurs.
    ///
    /// ## Important
    ///
    /// - The connection used for listening is held for the duration of the sequence
    /// - When iteration stops (break, return, throw, or natural completion), the
    ///   connection automatically executes UNLISTEN and is returned to the pool
    /// - Only one sequence can listen on a given channel per connection
    ///
    /// ## Example
    ///
    /// ```swift
    /// @Dependency(\.defaultDatabase) var db
    ///
    /// // Listen for string payloads
    /// for try await notification in try await db.notifications(channel: "updates") {
    ///     print("Update: \(notification.payload)")
    /// }
    /// ```
    ///
    /// ## With Timeout
    ///
    /// ```swift
    /// try await withThrowingTaskGroup(of: Void.self) { group in
    ///     group.addTask {
    ///         try await Task.sleep(for: .seconds(30))
    ///         throw CancellationError()
    ///     }
    ///
    ///     group.addTask {
    ///         for try await notification in try await db.notifications(channel: "updates") {
    ///             await handleUpdate(notification)
    ///         }
    ///     }
    ///
    ///     try await group.next()
    ///     group.cancelAll()
    /// }
    /// ```
    ///
    /// - Parameter channel: The PostgreSQL channel name to listen on
    /// - Returns: An AsyncSequence that yields notifications
    /// - Throws: Database errors if the LISTEN command fails
    public func notifications(
        channel: String
    ) async throws -> Database.NotificationStream {
        try await _notifications(channels: [channel])
    }

    /// Listens for typed notifications with automatic JSON decoding.
    ///
    /// This method is similar to `notifications(channel:)` but automatically
    /// decodes JSON payloads into the specified Codable type.
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
    /// for try await change: ReminderChange in try await db.notifications(channel: "reminders") {
    ///     print("Reminder \(change.id): \(change.action) - \(change.title)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The PostgreSQL channel name to listen on
    ///   - type: The Codable type to decode payloads into
    ///   - decoder: Optional custom JSON decoder (default: JSONDecoder())
    /// - Returns: An AsyncSequence that yields decoded payloads
    /// - Throws: Database errors, or decoding errors if payload is invalid JSON
    public func notifications<Payload: Decodable & Sendable>(
        channel: String,
        as type: Payload.Type = Payload.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> Database.TypedNotificationStream<Payload> {
        let stream = try await notifications(channel: channel)
        return Database.TypedNotificationStream(base: stream, decoder: decoder)
    }

    /// Listens for notifications on multiple PostgreSQL channels.
    ///
    /// This method subscribes to multiple channels simultaneously and returns
    /// notifications from any of them. This is more efficient than creating
    /// multiple separate listeners.
    ///
    /// ## Example
    ///
    /// ```swift
    /// for try await notification in try await db.notifications(channels: ["updates", "alerts"]) {
    ///     switch notification.channel {
    ///     case "updates":
    ///         await handleUpdate(notification.payload)
    ///     case "alerts":
    ///         await handleAlert(notification.payload)
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter channels: Array of PostgreSQL channel names to listen on
    /// - Returns: An AsyncSequence that yields notifications from any channel
    /// - Throws: Database errors if any LISTEN command fails
    public func notifications(
        channels: [String]
    ) async throws -> Database.NotificationStream {
        try await _notifications(channels: channels)
    }

    /// Internal implementation of notification listening.
    ///
    /// This method handles the core logic:
    /// 1. Acquires a dedicated connection
    /// 2. Executes LISTEN for each channel
    /// 3. Sets up the notification handler via postgres-nio
    /// 4. Returns an AsyncSequence backed by AsyncThrowingStream
    /// 5. Cleans up (UNLISTEN, close connection) when stream ends
    ///
    /// Note: This method will be implemented differently for PostgresClient vs other database types.
    /// For now, we provide a basic implementation that requires PostgresClient.
    private func _notifications(
        channels: [String]
    ) async throws -> Database.NotificationStream {
        guard !channels.isEmpty else {
            throw Database.Error.invalidNotificationChannels("At least one channel required")
        }

        // We need to cast to PostgresClient to get a dedicated connection
        guard let client = self as? PostgresClient else {
            throw Database.Error.notificationNotSupported(
                "Notifications currently only supported on PostgresClient. Found: \(type(of: self))"
            )
        }

        // Create the stream - let the compiler infer 'any Error'
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: Database.Notification.self,
            bufferingPolicy: .unbounded  // Buffer notifications so we don't drop any
        )

        // We need to get a dedicated connection and hold it for the lifetime of the stream
        // We'll do this in a detached task that runs until the stream is finished
        let listenerTask = Task.detached {
            do {
                try await client.withConnection { postgres in
                    // Set up notification handler
                    let listenerContext = postgres.addListener(channel: channels.first!) { _, notification in
                        let dbNotification = Database.Notification(
                            channel: notification.channel,
                            payload: notification.payload,
                            backendPID: notification.backendPID
                        )
                        continuation.yield(dbNotification)
                    }

                    // Execute LISTEN for each channel
                    let connection = Database.Connection(postgres)
                    for channel in channels {
                        try await connection.execute("LISTEN \(channel)")
                    }

                    // Keep the connection alive by waiting for cancellation
                    // When the stream is cancelled, this task will be cancelled too
                    try await withTaskCancellationHandler {
                        // Wait indefinitely - use a very long duration
                        try await Task.sleep(for: .seconds(Double.greatestFiniteMagnitude))
                    } onCancel: {
                        // Clean up when cancelled
                        listenerContext.stop()

                        // Execute UNLISTEN for each channel
                        Task {
                            for channel in channels {
                                try? await connection.execute("UNLISTEN \(channel)")
                            }
                            continuation.finish()
                        }
                    }
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }

        // Create cleanup closure that cancels the listener task
        let cleanup: @Sendable () async -> Void = {
            listenerTask.cancel()
            // Give it a moment to clean up
            try? await Task.sleep(for: .milliseconds(100))
        }

        return Database.NotificationStream(
            stream: stream,
            cleanup: cleanup
        )
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
    /// try await db.notify(channel: "updates", payload: "New data available")
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
    ///     try await db.notify(channel: "records", payload: "Record created")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The PostgreSQL channel name
    ///   - payload: The notification payload (must be a valid PostgreSQL string literal)
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(
        channel: String,
        payload: String
    ) async throws {
        try await write { db in
            // Escape single quotes in payload for SQL safety
            let escapedPayload = payload.replacingOccurrences(of: "'", with: "''")
            try await db.execute("NOTIFY \(channel), '\(escapedPayload)'")
        }
    }

    /// Sends a typed notification with automatic JSON encoding.
    ///
    /// This method encodes a Codable value to JSON and sends it as a notification
    /// payload. This is the recommended way to send structured data.
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
    ///     channel: "reminders",
    ///     payload: ReminderChange(id: 123, action: "updated", title: "Buy milk")
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - channel: The PostgreSQL channel name
    ///   - payload: The Codable value to encode and send
    ///   - encoder: Optional custom JSON encoder (default: JSONEncoder())
    /// - Throws: Database errors or encoding errors
    public func notify<Payload: Encodable & Sendable>(
        channel: String,
        payload: Payload,
        encoder: JSONEncoder = JSONEncoder()
    ) async throws {
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw Database.Error.invalidNotificationPayload(
                "Failed to encode payload to UTF-8 JSON string"
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
    /// try await db.notify(channel: "cache_invalidate")
    /// ```
    ///
    /// - Parameter channel: The PostgreSQL channel name
    /// - Throws: Database errors if the NOTIFY command fails
    public func notify(channel: String) async throws {
        try await write { db in
            try await db.execute("NOTIFY \(channel)")
        }
    }
}
