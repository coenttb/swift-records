import Testing
import Foundation
import Dependencies
import DependenciesTestSupport
import PostgresNIO
@testable import Records
import RecordsTestSupport

@Suite(
    "PostgreSQL LISTEN/NOTIFY Integration",
//    .serialized,
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.withReminderData()
    }
)
struct NotificationIntegrationTests {
    @Dependency(\.defaultDatabase) var database

    // MARK: - Basic Notification Tests

    struct SimplePayload: Codable, Equatable, Sendable {
        let message: String
    }

    @Test("Send and receive basic string notification")
    func basicNotification() async throws {
        let channel = try ChannelName(validating: "test_basic_\(UUID().uuidString)")
        let payload = SimplePayload(message: "Hello, PostgreSQL!")

        // Get stream and readiness signal
        let (stream, ready): (Database.NotificationStream<SimplePayload>, AsyncStream<Void>) =
            try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Start listener in background
            group.addTask {
                var receivedCount = 0
                for try await received in stream {
                    #expect(received == payload)
                    receivedCount += 1

                    // Exit after receiving one notification - stream cleans up automatically
                    if receivedCount == 1 {
                        break
                    }
                }
                #expect(receivedCount == 1)
            }

            // Wait for LISTEN to complete
            for await _ in ready { break }

            // Now safe to send
            try await database.notify(channel: channel, payload: payload)

            // Wait for listener to complete naturally
            try await group.waitForAll()
        }
    }

    struct EmptyPayload: Codable, Equatable, Sendable {
        // Empty struct encodes to {}
    }

    @Test("Send notification without payload")
    func notificationWithoutPayload() async throws {
        let channel = try ChannelName(validating: "test_no_payload_\(UUID().uuidString)")
        let payload = EmptyPayload()

        let (stream, ready) = try await database.notifications(on: channel, expecting: EmptyPayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received == payload)
                    break  // Stream cleans up automatically
                }
            }

            for await _ in ready { break }
            try await database.notify(channel: channel, payload: payload)

            try await group.waitForAll()
        }
    }

    // MARK: - Typed Notification Tests

    struct TestMessage: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let timestamp: Date
    }

    @Test("Send and receive typed notification")
    func typedNotification() async throws {
        let channel = try ChannelName(validating: "test_typed_\(UUID().uuidString)")
        let message = TestMessage(
            id: 42,
            action: "created",
            timestamp: Date()
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let (stream, ready) = try await database.notifications(
            on: channel,
            expecting: TestMessage.self,
            decoder: decoder
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received.id == message.id)
                    #expect(received.action == message.action)
                    // Allow small timestamp difference due to encoding/decoding
                    #expect(abs(received.timestamp.timeIntervalSince(message.timestamp)) < 1.0)
                    break
                }
            }

            for await _ in ready { break }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try await database.notify(channel: channel, payload: message, encoder: encoder)

            try await group.waitForAll()
        }
    }

    // MARK: - Multiple Notifications Tests

    @Test("Receive multiple notifications on same channel")
    func multipleNotifications() async throws {
        let channel = try ChannelName(validating: "test_multiple_\(UUID().uuidString)")
        let count = 5

        let (stream, ready) = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var received: [SimplePayload] = []
                for try await notification in stream {
                    received.append(notification)
                    if received.count == count {
                        break
                    }
                }
                #expect(received.count == count)
                // Verify FIFO ordering
                for i in 0..<count {
                    #expect(received[i] == SimplePayload(message: "Message \(i)"))
                }
            }

            // Wait for LISTEN to complete
            for await _ in ready { break }

            // Send multiple notifications
            for i in 0..<count {
                try await database.notify(channel: channel, payload: SimplePayload(message: "Message \(i)"))
                // Small delay between notifications
                try await Task.sleep(for: .milliseconds(10))
            }

            try await group.waitForAll()
        }
    }

    // MARK: - Multiple Channels Tests

    @Test("Channel isolation - listeners only receive their channel's notifications")
    func channelIsolation() async throws {
        let channelA = try ChannelName(validating: "test_channel_a_\(UUID().uuidString)")
        let channelB = try ChannelName(validating: "test_channel_b_\(UUID().uuidString)")

        let (streamA, readyA) = try await database.notifications(on: channelA, expecting: SimplePayload.self)
        let (streamB, readyB) = try await database.notifications(on: channelB, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Listener A - should only receive from channel A
            group.addTask {
                var receivedA: [SimplePayload] = []
                for try await notification in streamA {
                    receivedA.append(notification)
                    if receivedA.count == 1 {
                        break
                    }
                }
                #expect(receivedA.count == 1)
                #expect(receivedA[0].message == "For Channel A")
            }

            // Listener B - should only receive from channel B
            group.addTask {
                var receivedB: [SimplePayload] = []
                for try await notification in streamB {
                    receivedB.append(notification)
                    if receivedB.count == 1 {
                        break
                    }
                }
                #expect(receivedB.count == 1)
                #expect(receivedB[0].message == "For Channel B")
            }

            // Wait for both listeners to be ready
            for await _ in readyA { break }
            for await _ in readyB { break }

            // Send to channel A - only listener A should receive
            try await database.notify(channel: channelA, payload: SimplePayload(message: "For Channel A"))

            // Send to channel B - only listener B should receive
            try await database.notify(channel: channelB, payload: SimplePayload(message: "For Channel B"))

            try await group.waitForAll()
        }
    }

    // TODO: Multi-channel listening not yet implemented
    // The current API only supports listening to a single channel at a time
    // Future enhancement: Add notifications(channels: [ChannelName]) method
    /*
    @Test("Listen to multiple channels")
    func multipleChannels() async throws {
        let channel1 = try ChannelName(validating: "test_multi_1_\(UUID().uuidString)")
        let channel2 = try ChannelName(validating: "test_multi_2_\(UUID().uuidString)")

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var receivedChannels: Set<ChannelName> = []
                for try await notification in try await self.database.notifications(
                    channels: [channel1, channel2]
                ) {
                    receivedChannels.insert(notification.channel)
                    if receivedChannels.count == 2 {
                        break
                    }
                }
                #expect(receivedChannels.contains(channel1))
                #expect(receivedChannels.contains(channel2))
            }

            try await Task.sleep(for: .milliseconds(200))

            try await database.notify(channel: channel1, payload: "From channel 1")
            try await Task.sleep(for: .milliseconds(50))
            try await database.notify(channel: channel2, payload: "From channel 2")

            try await group.next()
            group.cancelAll()
        }
    }
    */

    // MARK: - Cancellation Tests

    @Test("Handle cancellation gracefully")
    func cancellation() async throws {
        let channel = try ChannelName(validating: "test_cancel_\(UUID().uuidString)")

        let (stream, ready) = try await database.notifications(on: channel, expecting: SimplePayload.self)

        let task = Task {
            var count = 0
            for try await _ in stream {
                count += 1
            }
            return count
        }

        // Wait for LISTEN to complete
        for await _ in ready { break }

        // Give it a moment
        try await Task.sleep(for: .milliseconds(100))

        // Cancel the task
        task.cancel()

        // Give it time to clean up
        try await Task.sleep(for: .milliseconds(200))

        // Check that task completes
        let result = await task.result
        // Cancellation should have occurred
        _ = result  // Don't assert on the specific error type - just that it completes
    }

    // MARK: - Error Handling Tests

    @Test("Handle JSON decoding errors gracefully")
    func jsonDecodingError() async throws {
        let channel = try ChannelName(validating: "test_decode_error_\(UUID().uuidString)")

        let (stream, ready) = try await database.notifications(on: channel, expecting: TestMessage.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await _: TestMessage in stream {
                        Issue.record("Should have thrown decoding error")
                        break
                    }
                } catch let error as Database.Error {
                    switch error {
                    case .notificationDecodingFailed:
                        break // Expected
                    default:
                        Issue.record("Wrong error type: \(error)")
                    }
                } catch {
                    Issue.record("Wrong error type: \(error)")
                }
            }

            for await _ in ready { break }

            // Send invalid JSON
            try await database.notify(channel: channel, payload: "not valid json")

            try await group.waitForAll()
        }
    }

    // TODO: Test for empty channel list - requires multi-channel API
    // Currently the single-channel API requires a channel parameter, so this test isn't applicable
    /*
    @Test("Require at least one channel")
    func emptyChannelList() async throws {
        await #expect(throws: Database.Error.self) {
            _ = try await database.notifications(channels: [])
        }
    }
    */

    // MARK: - SQL Injection Protection

    @Test("Escape single quotes in payload")
    func sqlInjectionProtection() async throws {
        let channel = try ChannelName(validating: "test_injection_\(UUID().uuidString)")
        let payload = SimplePayload(message: "It's a beautiful day, isn't it?")

        let (stream, ready) = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received == payload)
                    break
                }
            }

            for await _ in ready { break }
            try await database.notify(channel: channel, payload: payload)

            try await group.waitForAll()
        }
    }

    // MARK: - Transaction Behavior Tests

    @Test("Notifications not sent on transaction rollback")
    func transactionRollback() async throws {
        let channel = try ChannelName(validating: "test_rollback_\(UUID().uuidString)")
        let payload = SimplePayload(message: "should not be sent")

        let (stream, ready) = try await database.notifications(on: channel, expecting: SimplePayload.self)

        // Start listener
        let listenerTask = Task {
            var receivedCount = 0
            for try await _ in stream {
                receivedCount += 1
            }
            return receivedCount
        }

        // Wait for LISTEN to complete
        for await _ in ready { break }

        // Send notification in transaction that rolls back
        do {
            try await database.withTransaction { db in
                try await db.notify(channel: channel, payload: payload)
                throw CancellationError() // Force rollback
            }
        } catch {
            // Expected - transaction rolled back
        }

        // Wait a moment to ensure no notification arrives
        try await Task.sleep(for: .milliseconds(100))

        // Cancel listener - it should have received ZERO notifications
        listenerTask.cancel()
        let count = await listenerTask.result

        // Verify listener received nothing (rollback prevented notification)
        switch count {
        case .success(let c):
            #expect(c == 0, "Expected 0 notifications after rollback, got \(c)")
        case .failure:
            // Task was cancelled, which is expected
            break
        }
    }

    @Test("Notifications within transactions")
    func transactionNotifications() async throws {
        let channel = try ChannelName(validating: "test_transaction_\(UUID().uuidString)")
        let payload = SimplePayload(message: "committed")

        let (stream, ready) = try await database.notifications(on: channel, expecting: SimplePayload.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await received in stream {
                    #expect(received == payload)
                    break
                }
            }

            for await _ in ready { break }

            // Notification should only be visible after commit
            try await database.withTransaction { db in
                try await db.notify(channel: channel, payload: payload)
            }

            try await group.waitForAll()
        }
    }

    // MARK: - Real-world Use Case Tests

    struct ReminderChange: Codable, Equatable, Sendable {
        let id: Int
        let action: String
        let title: String
    }

    @Test("Real-world reminder change notification")
    func realWorldUseCase() async throws {
        let channel = try ChannelName(validating: "reminder_changes")
        let change = ReminderChange(
            id: 123,
            action: "updated",
            title: "Buy groceries"
        )

        let (stream, ready) = try await database.notifications(on: channel, expecting: ReminderChange.self)

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Simulate real-time UI update listener
            group.addTask {
                for try await received in stream {
                    #expect(received == change)
                    // In real app: await MainActor.run { updateUI(with: received) }
                    break
                }
            }

            for await _ in ready { break }

            // Simulate database write + notification
            try await database.write { db in
                // In real app: try await Reminder.update(...)
                try await db.notify(channel: channel, payload: change)
            }

            try await group.waitForAll()
        }
    }
}
