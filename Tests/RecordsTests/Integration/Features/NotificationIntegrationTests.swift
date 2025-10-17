import Testing
import Foundation
import Dependencies
import DependenciesTestSupport
import PostgresNIO
@testable import Records
import RecordsTestSupport

@Suite(
    "PostgreSQL LISTEN/NOTIFY Integration",
    .dependencies {
        $0.envVars = .development
        $0.defaultDatabase = Database.TestDatabase.minimal()
    }
)
struct NotificationIntegrationTests {
    @Dependency(\.defaultDatabase) var database

    // MARK: - Basic Notification Tests

    @Test("Send and receive basic string notification")
    func basicNotification() async throws {
        let channel = "test_basic_\(UUID().uuidString)"
        let payload = "Hello, PostgreSQL!"

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Start listener in background
            group.addTask {
                var receivedCount = 0
                for try await notification in try await self.database.notifications(channel: channel) {
                    #expect(notification.channel == channel)
                    #expect(notification.payload == payload)
                    receivedCount += 1

                    // Exit after receiving one notification
                    if receivedCount == 1 {
                        break
                    }
                }
                #expect(receivedCount == 1)
            }

            // Give listener time to start
            try await Task.sleep(for: .milliseconds(200))

            // Send notification
            try await database.notify(channel: channel, payload: payload)

            // Wait for listener to receive
            try await group.next()
            group.cancelAll()
        }
    }

    @Test("Send notification without payload")
    func notificationWithoutPayload() async throws {
        let channel = "test_no_payload_\(UUID().uuidString)"

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await notification in try await self.database.notifications(channel: channel) {
                    #expect(notification.channel == channel)
                    #expect(notification.payload.isEmpty)
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(200))
            try await database.notify(channel: channel)

            try await group.next()
            group.cancelAll()
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
        let channel = "test_typed_\(UUID().uuidString)"
        let message = TestMessage(
            id: 42,
            action: "created",
            timestamp: Date()
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                for try await received: TestMessage in try await self.database.notifications(
                    channel: channel,
                    decoder: decoder
                ) {
                    #expect(received.id == message.id)
                    #expect(received.action == message.action)
                    // Allow small timestamp difference due to encoding/decoding
                    #expect(abs(received.timestamp.timeIntervalSince(message.timestamp)) < 1.0)
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(200))

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try await database.notify(channel: channel, payload: message, encoder: encoder)

            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Multiple Notifications Tests

    @Test("Receive multiple notifications on same channel")
    func multipleNotifications() async throws {
        let channel = "test_multiple_\(UUID().uuidString)"
        let count = 5

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var received: [String] = []
                for try await notification in try await self.database.notifications(channel: channel) {
                    received.append(notification.payload)
                    if received.count == count {
                        break
                    }
                }
                #expect(received.count == count)
                for i in 0..<count {
                    #expect(received[i] == "Message \(i)")
                }
            }

            try await Task.sleep(for: .milliseconds(200))

            // Send multiple notifications
            for i in 0..<count {
                try await database.notify(channel: channel, payload: "Message \(i)")
                // Small delay between notifications
                try await Task.sleep(for: .milliseconds(10))
            }

            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Multiple Channels Tests

    @Test("Listen to multiple channels")
    func multipleChannels() async throws {
        let channel1 = "test_multi_1_\(UUID().uuidString)"
        let channel2 = "test_multi_2_\(UUID().uuidString)"

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var receivedChannels: Set<String> = []
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

    // MARK: - Cancellation Tests

    @Test("Handle cancellation gracefully")
    func cancellation() async throws {
        let channel = "test_cancel_\(UUID().uuidString)"

        let task = Task {
            var count = 0
            for try await _ in try await database.notifications(channel: channel) {
                count += 1
            }
            return count
        }

        // Give it time to start
        try await Task.sleep(for: .milliseconds(200))

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
        let channel = "test_decode_error_\(UUID().uuidString)"

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    for try await _: TestMessage in try await self.database.notifications(channel: channel) {
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

            try await Task.sleep(for: .milliseconds(200))

            // Send invalid JSON
            try await database.notify(channel: channel, payload: "not valid json")

            try await group.next()
            group.cancelAll()
        }
    }

    @Test("Require at least one channel")
    func emptyChannelList() async throws {
        await #expect(throws: Database.Error.self) {
            _ = try await database.notifications(channels: [])
        }
    }

    // MARK: - SQL Injection Protection

    @Test("Escape single quotes in payload")
    func sqlInjectionProtection() async throws {
        let channel = "test_injection_\(UUID().uuidString)"
        let payload = "It's a beautiful day, isn't it?"

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await notification in try await self.database.notifications(channel: channel) {
                    #expect(notification.payload == payload)
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(200))
            try await database.notify(channel: channel, payload: payload)

            try await group.next()
            group.cancelAll()
        }
    }

    // MARK: - Transaction Behavior Tests

    @Test("Notifications within transactions")
    func transactionNotifications() async throws {
        let channel = "test_transaction_\(UUID().uuidString)"

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await notification in try await self.database.notifications(channel: channel) {
                    #expect(notification.payload == "committed")
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(200))

            // Notification should only be visible after commit
            try await database.withTransaction { db in
                try await db.notify(channel: channel, payload: "committed")
            }

            try await group.next()
            group.cancelAll()
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
        let channel = "reminder_changes"
        let change = ReminderChange(
            id: 123,
            action: "updated",
            title: "Buy groceries"
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            // Simulate real-time UI update listener
            group.addTask {
                for try await received: ReminderChange in try await self.database.notifications(channel: channel) {
                    #expect(received == change)
                    // In real app: await MainActor.run { updateUI(with: received) }
                    break
                }
            }

            try await Task.sleep(for: .milliseconds(200))

            // Simulate database write + notification
            try await database.write { db in
                // In real app: try await Reminder.update(...)
                try await db.notify(channel: channel, payload: change)
            }

            try await group.next()
            group.cancelAll()
        }
    }
}
