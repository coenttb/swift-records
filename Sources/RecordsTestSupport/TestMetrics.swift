import Foundation
import ResourcePool
import struct ResourcePool.Statistics
import struct ResourcePool.Metrics

extension LazyTestDatabase {
    /// Log current pool statistics
    ///
    /// Use this to debug test database pool behavior and resource usage.
    /// Particularly helpful for diagnosing thundering herd issues and wait times.
    ///
    /// Example:
    /// ```swift
    /// @Test func myTest() async throws {
    ///     await db.logStatistics(label: "BeforeTest")
    ///     // ... test operations ...
    ///     await db.logStatistics(label: "AfterTest")
    /// }
    /// ```
    public func logStatistics(label: String = "TestDB") async {
        let stats = await self.statistics
        print("""
        [\(label)] Pool Statistics:
          Available: \(stats.available)
          Leased: \(stats.leased)
          Capacity: \(stats.capacity)
          Queue Depth: \(stats.waitQueueDepth)
          Utilization: \(String(format: "%.1f%%", stats.utilization * 100))
          Backpressure: \(stats.hasBackpressure ? "⚠️ YES" : "✅ NO")
        """)
    }

    /// Log comprehensive metrics
    ///
    /// Provides detailed insight into pool behavior including:
    /// - Handoff rate (key metric for thundering herd prevention)
    /// - Wait times (should be minimal for suite-level pools)
    /// - Failure counts (validation, creation, reset errors)
    ///
    /// Example:
    /// ```swift
    /// @Suite("Heavy Tests", .dependency(\.defaultDatabase, try await Database.TestDatabase.withPooled(setupMode: .withReminderData, capacity: 5)))
    /// struct HeavyTests {
    ///     @Dependency(\.defaultDatabase) var db
    ///
    ///     @Test(.enabled(if: ProcessInfo.processInfo.environment["DEBUG_METRICS"] != nil))
    ///     func showMetrics() async {
    ///         await (db as? LazyTestDatabase)?.logMetrics(label: "HeavyTests")
    ///     }
    /// }
    /// ```
    public func logMetrics(label: String = "TestDB") async {
        let metrics = await self.metrics
        let stats = metrics.currentStatistics

        print("""
        [\(label)] Pool Metrics:
          Total Acquisitions: \(metrics.totalAcquisitions)
          Timeouts: \(metrics.timeouts)
          Validation Failures: \(metrics.validationFailures)
          Reset Failures: \(metrics.resetFailures)
          Creation Failures: \(metrics.creationFailures)
          Waiters Queued: \(metrics.waitersQueued)
          Direct Handoffs: \(metrics.directHandoffs)
          Handoff Rate: \(String(format: "%.1f%%", metrics.handoffRate * 100))
          Avg Wait Time: \(metrics.averageWaitTime.map { "\(String(format: "%.2f", $0.components.seconds))s" } ?? "N/A")
          Current Available: \(stats.available)
          Current Leased: \(stats.leased)
        """)
    }

    /// Assert pool health for debugging
    ///
    /// Checks that the pool is in a healthy state. Useful for debugging
    /// test failures related to resource exhaustion.
    ///
    /// Example:
    /// ```swift
    /// @Test func stressTest() async throws {
    ///     // Run many concurrent operations
    ///     await withTaskGroup(of: Void.self) { group in
    ///         for _ in 1...100 {
    ///             group.addTask {
    ///                 try? await db.read { ... }
    ///             }
    ///         }
    ///     }
    ///
    ///     // Verify pool is healthy
    ///     await (db as? LazyTestDatabase)?.assertPoolHealth()
    /// }
    /// ```
    public func assertPoolHealth() async {
        let stats = await self.statistics
        let metrics = await self.metrics

        if metrics.timeouts > 0 {
            print("⚠️ Pool Health Warning: \(metrics.timeouts) timeout(s) occurred")
        }

        if metrics.validationFailures > 0 {
            print("⚠️ Pool Health Warning: \(metrics.validationFailures) validation failure(s)")
        }

        if metrics.creationFailures > 0 {
            print("⚠️ Pool Health Warning: \(metrics.creationFailures) creation failure(s)")
        }

        if stats.hasBackpressure {
            print("⚠️ Pool Health Warning: Backpressure detected (queue depth: \(stats.waitQueueDepth))")
        }

        if metrics.handoffRate < 0.5 && metrics.totalAcquisitions > 10 {
            print("⚠️ Pool Health Warning: Low handoff rate (\(String(format: "%.1f%%", metrics.handoffRate * 100))) - possible thundering herd")
        }
    }
}

// MARK: - Environment-based Metrics Logging

extension LazyTestDatabase {
    /// Conditionally log metrics based on environment variable
    ///
    /// Set `RECORDS_DEBUG_METRICS=1` to enable automatic metrics logging.
    /// This is useful for CI/CD pipelines or debugging test failures.
    ///
    /// Example usage in tests:
    /// ```swift
    /// @Test func myTest() async throws {
    ///     await db.logMetricsIfEnabled(label: "MyTest.Start")
    ///     // ... test operations ...
    ///     await db.logMetricsIfEnabled(label: "MyTest.End")
    /// }
    /// ```
    ///
    /// Run tests with metrics:
    /// ```bash
    /// RECORDS_DEBUG_METRICS=1 swift test
    /// ```
    public func logMetricsIfEnabled(label: String = "TestDB") async {
        guard ProcessInfo.processInfo.environment["RECORDS_DEBUG_METRICS"] != nil else {
            return
        }
        await logMetrics(label: label)
    }

    /// Conditionally log statistics based on environment variable
    public func logStatisticsIfEnabled(label: String = "TestDB") async {
        guard ProcessInfo.processInfo.environment["RECORDS_DEBUG_METRICS"] != nil else {
            return
        }
        await logStatistics(label: label)
    }
}
