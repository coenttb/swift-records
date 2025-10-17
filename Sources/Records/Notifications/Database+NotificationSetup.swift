import Foundation
import StructuredQueriesPostgres
import PostgresNIO

// MARK: - Channel Name Validation

/// Validates that a channel name is safe for use in SQL.
///
/// This prevents SQL injection by ensuring the channel name only contains
/// alphanumeric characters, underscores, and hyphens (valid PostgreSQL identifier characters).
///
/// - Parameter channelName: The channel name to validate
/// - Throws: Database.Error.invalidNotificationChannels if name contains invalid characters
fileprivate func validateChannelName(_ channelName: String) throws {
    let allowedCharacterSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
    guard channelName.unicodeScalars.allSatisfy({ allowedCharacterSet.contains($0) }) else {
        throw Database.Error.invalidNotificationChannels(
            "Invalid channel name '\(channelName)': must contain only alphanumeric characters, underscores, and hyphens"
        )
    }
    guard !channelName.isEmpty else {
        throw Database.Error.invalidNotificationChannels("Channel name cannot be empty")
    }
    guard channelName.count <= 63 else {
        throw Database.Error.invalidNotificationChannels(
            "Channel name '\(channelName)' exceeds PostgreSQL's 63 character limit"
        )
    }
}

// MARK: - Notification Setup Operations

extension Database.Connection.`Protocol` {

    // MARK: - Trigger Function Creation

    /// Creates a trigger function that sends notifications on database changes.
    ///
    /// This function creates a PostgreSQL trigger function that automatically sends
    /// notifications when rows are inserted, updated, or deleted.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.createNotificationTriggerFunction(
    ///         name: "notify_reminder_changes",
    ///         channel: "reminder_events",
    ///         includeOldValues: false
    ///     )
    /// }
    /// ```
    ///
    /// The function sends JSON payloads with the structure:
    /// ```json
    /// {
    ///   "operation": "INSERT"|"UPDATE"|"DELETE",
    ///   "new": { ... },  // NEW row (for INSERT and UPDATE)
    ///   "old": { ... }   // OLD row (for UPDATE and DELETE, if includeOldValues is true)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The trigger function name
    ///   - channel: The notification channel name
    ///   - includeOldValues: Whether to include OLD row values (default: false)
    /// - Throws: Database error if function creation fails
    public func createNotificationTriggerFunction(
        name: String,
        channel: String,
        includeOldValues: Bool = false
    ) async throws {
        try validateChannelName(channel)

        let payloadExpression: String
        if includeOldValues {
            payloadExpression = """
            json_build_object(
                  'operation', TG_OP,
                  'new', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END,
                  'old', CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN row_to_json(OLD) ELSE NULL END
                )
            """
        } else {
            payloadExpression = """
            json_build_object(
                  'operation', TG_OP,
                  'new', CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN row_to_json(NEW) ELSE NULL END
                )
            """
        }

        let sql = """
            CREATE OR REPLACE FUNCTION \(name.quoted())() RETURNS trigger AS $$
            DECLARE
              payload text;
            BEGIN
              payload := \(payloadExpression)::text;
              PERFORM pg_notify(\(channel.quoted(.text)), payload);
              RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
            END;
            $$ LANGUAGE plpgsql
            """

        print("📢 Creating notification trigger function '\(name)' for channel '\(channel)'")
        do {
            try await execute(sql)
            print("✅ Successfully created notification trigger function '\(name)'")
        } catch {
            print("❌ Failed to create notification trigger function: \(String(reflecting: error))")
            throw error
        }
    }

    /// Drops a notification trigger function.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.dropNotificationTriggerFunction(name: "notify_reminder_changes")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The trigger function name
    ///   - ifExists: Whether to skip if function doesn't exist (default: true)
    /// - Throws: Database error if function drop fails
    public func dropNotificationTriggerFunction(
        name: String,
        ifExists: Bool = true
    ) async throws {
        let ifExistsClause = ifExists ? "IF EXISTS " : ""
        let sql = "DROP FUNCTION \(ifExistsClause)\(name.quoted())()"

        print("📢 Dropping notification trigger function '\(name)'")
        do {
            try await execute(sql)
            print("✅ Successfully dropped notification trigger function '\(name)'")
        } catch {
            print("❌ Failed to drop notification trigger function: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Trigger Creation

    /// Creates a trigger that calls a notification trigger function.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     // First create the function
    ///     try await db.createNotificationTriggerFunction(
    ///         name: "notify_reminder_changes",
    ///         channel: "reminder_events"
    ///     )
    ///
    ///     // Then create the trigger
    ///     try await db.createNotificationTrigger(
    ///         on: "reminders",
    ///         name: "reminders_notify",
    ///         functionName: "notify_reminder_changes",
    ///         events: [.insert, .update, .delete]
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - name: The trigger name
    ///   - functionName: The trigger function to call
    ///   - events: The database events to trigger on
    ///   - timing: When to fire the trigger (default: .after)
    /// - Throws: Database error if trigger creation fails
    public func createNotificationTrigger(
        on table: String,
        name: String,
        functionName: String,
        events: Set<Database.Notification.TriggerEvent>,
        timing: Database.Notification.TriggerTiming = .after
    ) async throws {
        guard !events.isEmpty else {
            throw Database.Error.invalidNotificationChannels("At least one trigger event required")
        }

        let eventList = events.map(\.rawValue).sorted().joined(separator: " OR ")
        let timingKeyword = timing.rawValue

        let sql = """
            CREATE TRIGGER \(name.quoted())
            \(timingKeyword) \(eventList) ON \(table.quoted())
            FOR EACH ROW EXECUTE FUNCTION \(functionName.quoted())()
            """

        print("📢 Creating notification trigger '\(name)' on table '\(table)'")
        do {
            try await execute(sql)
            print("✅ Successfully created notification trigger '\(name)'")
        } catch {
            print("❌ Failed to create notification trigger: \(String(reflecting: error))")
            throw error
        }
    }

    /// Drops a notification trigger.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.dropNotificationTrigger(name: "reminders_notify", on: "reminders")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The trigger name
    ///   - table: The table name
    ///   - ifExists: Whether to skip if trigger doesn't exist (default: true)
    /// - Throws: Database error if trigger drop fails
    public func dropNotificationTrigger(
        name: String,
        on table: String,
        ifExists: Bool = true
    ) async throws {
        let ifExistsClause = ifExists ? "IF EXISTS " : ""
        let sql = "DROP TRIGGER \(ifExistsClause)\(name.quoted()) ON \(table.quoted())"

        print("📢 Dropping notification trigger '\(name)' from table '\(table)'")
        do {
            try await execute(sql)
            print("✅ Successfully dropped notification trigger '\(name)'")
        } catch {
            print("❌ Failed to drop notification trigger: \(String(reflecting: error))")
            throw error
        }
    }

    // MARK: - Complete Setup Helpers

    /// Complete notification channel setup for a table.
    ///
    /// This convenience function performs all necessary steps to set up database
    /// notifications for a table:
    /// 1. Creates a trigger function that sends notifications
    /// 2. Creates a trigger that calls the function on specified events
    ///
    /// The notifications are sent as JSON payloads containing the operation type
    /// and the affected row data.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.setupNotificationChannel(
    ///         on: "reminders",
    ///         channel: "reminder_events",
    ///         events: [.insert, .update, .delete],
    ///         includeOldValues: false
    ///     )
    /// }
    /// ```
    ///
    /// After setup, listen for notifications:
    /// ```swift
    /// struct ReminderEvent: Codable {
    ///     let operation: String
    ///     let new: Reminder?
    ///     let old: Reminder?
    /// }
    ///
    /// for try await event: ReminderEvent in try await db.notifications(channel: "reminder_events") {
    ///     print("\(event.operation): \(event.new)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - channel: The notification channel name
    ///   - events: The database events to trigger on (default: [.insert, .update, .delete])
    ///   - includeOldValues: Whether to include OLD row values (default: false)
    ///   - timing: When to fire the trigger (default: .after)
    /// - Returns: The channel name (for convenience)
    /// - Throws: Database error if setup fails
    @discardableResult
    public func setupNotificationChannel(
        on table: String,
        channel: String,
        events: Set<Database.Notification.TriggerEvent> = [.insert, .update, .delete],
        includeOldValues: Bool = false,
        timing: Database.Notification.TriggerTiming = .after
    ) async throws -> String {
        try validateChannelName(channel)

        let functionName = "\(table)_\(channel)_notify"
        let triggerName = "\(table)_\(channel)_trigger"

        print("📢 Setting up notification channel '\(channel)' for table '\(table)'")

        // 1. Create trigger function
        try await createNotificationTriggerFunction(
            name: functionName,
            channel: channel,
            includeOldValues: includeOldValues
        )

        // 2. Drop existing trigger (if exists)
        try await dropNotificationTrigger(name: triggerName, on: table, ifExists: true)

        // 3. Create trigger
        try await createNotificationTrigger(
            on: table,
            name: triggerName,
            functionName: functionName,
            events: events,
            timing: timing
        )

        print("✅ Successfully set up notification channel '\(channel)' for table '\(table)'")
        return channel
    }

    /// Complete type-safe notification channel setup using a schema.
    ///
    /// This is the type-safe version of `setupNotificationChannel` that uses a
    /// `NotificationChannelSchema` to couple the channel name with its payload type.
    ///
    /// ```swift
    /// struct ReminderEventsChannel: NotificationChannelSchema {
    ///     static let channelName = "reminder_events"
    ///
    ///     struct Payload: Codable, Sendable {
    ///         let operation: String
    ///         let new: Reminder?
    ///         let old: Reminder?
    ///     }
    /// }
    ///
    /// try await db.write { db in
    ///     try await db.setupNotificationChannel(
    ///         schema: ReminderEventsChannel.self,
    ///         on: "reminders",
    ///         events: [.insert, .update, .delete]
    ///     )
    /// }
    ///
    /// // Listen with type safety
    /// for try await event in try await db.notifications(schema: ReminderEventsChannel.self) {
    ///     print("\(event.operation): \(event.new)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - table: The table name
    ///   - events: The database events to trigger on (default: [.insert, .update, .delete])
    ///   - includeOldValues: Whether to include OLD row values (default: false)
    ///   - timing: When to fire the trigger (default: .after)
    /// - Returns: A type-safe channel instance
    /// - Throws: Database error if setup fails
    @discardableResult
    public func setupNotificationChannel<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type,
        on table: String,
        events: Set<Database.Notification.TriggerEvent> = [.insert, .update, .delete],
        includeOldValues: Bool = false,
        timing: Database.Notification.TriggerTiming = .after
    ) async throws -> Database.Notification.Channel<Schema.Payload> {
        try await setupNotificationChannel(
            on: table,
            channel: Schema.channelName,
            events: events,
            includeOldValues: includeOldValues,
            timing: timing
        )
        return Schema.channel
    }

    /// Removes notification channel setup from a table.
    ///
    /// This function removes the trigger and trigger function associated with a
    /// notification channel.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.removeNotificationChannel(
    ///         on: "reminders",
    ///         channel: "reminder_events"
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - table: The table name
    ///   - channel: The notification channel name
    /// - Throws: Database error if removal fails
    public func removeNotificationChannel(
        on table: String,
        channel: String
    ) async throws {
        let functionName = "\(table)_\(channel)_notify"
        let triggerName = "\(table)_\(channel)_trigger"

        print("📢 Removing notification channel '\(channel)' from table '\(table)'")

        // 1. Drop trigger
        try await dropNotificationTrigger(name: triggerName, on: table, ifExists: true)

        // 2. Drop function
        try await dropNotificationTriggerFunction(name: functionName, ifExists: true)

        print("✅ Successfully removed notification channel '\(channel)' from table '\(table)'")
    }

    /// Removes type-safe notification channel setup using a schema.
    ///
    /// ```swift
    /// try await db.write { db in
    ///     try await db.removeNotificationChannel(
    ///         schema: ReminderEventsChannel.self,
    ///         on: "reminders"
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - schema: The notification channel schema type
    ///   - table: The table name
    /// - Throws: Database error if removal fails
    public func removeNotificationChannel<Schema: Database.Notification.ChannelSchema>(
        schema: Schema.Type,
        on table: String
    ) async throws {
        try await removeNotificationChannel(on: table, channel: Schema.channelName)
    }
}
