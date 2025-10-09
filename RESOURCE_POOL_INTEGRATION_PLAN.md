# ResourcePool Integration Plan for swift-records

**Date**: 2025-10-09
**Status**: 📋 Planning
**Objective**: Integrate swift-resource-pool for test database management to improve observability, fairness, and thundering herd prevention

## Executive Summary

Integrate `swift-resource-pool` to enhance the current working test database solution with:
- ✅ Better thundering herd prevention (direct handoff vs broadcast)
- ✅ FIFO fairness guarantees (no test starvation)
- ✅ Comprehensive metrics (wait times, handoff rates, utilization)
- ✅ Sophisticated pre-warming (synchronous first resource + background remainder)
- ✅ Resource validation and cycling
- ✅ Timeout handling per test

**Scope**: Test database pooling only (NOT PostgreSQL connection pooling)

## Current State

### What Works (As of 2025-10-08)

From `PARALLEL_TEST_DEBUGGING.md`:

```swift
// Each suite creates its own database directly
private actor DatabaseManager {
    private var database: Database.TestDatabase?

    func getDatabase() async throws -> Database.TestDatabase {
        if let database = database {
            return database
        }

        // Direct creation bypasses pool actor bottleneck
        let newDatabase = try await Database.testDatabase(
            configuration: nil,
            prefix: "test"
        )

        // Setup schema
        try await newDatabase.createReminderSchema()
        try await newDatabase.insertReminderSampleData()

        self.database = newDatabase
        return newDatabase
    }
}

public final class LazyTestDatabase: Database.Writer {
    private let manager: DatabaseManager

    init(setupMode: SetupMode, preWarm: Bool = true) {
        self.manager = DatabaseManager(setupMode: setupMode.databaseSetupMode)

        // Simple pre-warming
        if preWarm {
            Task.detached { [manager] in
                _ = try? await manager.getDatabase()
            }
        }
    }
}
```

**Key Success**: Tests pass with cmd+U parallel execution!

### Current Limitations

1. **No metrics**: Can't observe wait times, utilization, or handoff rates
2. **Simple pre-warming**: Just `Task.detached`, no coordination
3. **No FIFO guarantees**: If multiple tests wait, order is undefined
4. **No timeout handling**: Tests wait indefinitely
5. **No resource validation**: Can't detect stale/broken databases
6. **No resource cycling**: Databases never refreshed

## Integration Strategy

### Principle: Enhance, Don't Replace

Keep the working architecture, enhance with ResourcePool features:

```
Before (Working):
Test Suite → LazyTestDatabase → DatabaseManager → Database.testDatabase() → PostgreSQL

After (Enhanced):
Test Suite → LazyTestDatabase → ResourcePool<TestDatabase> → Database.testDatabase() → PostgreSQL
                                        ↑
                              Direct handoff, metrics, fairness
```

### What NOT to Change

❌ **Don't touch PostgreSQL connection pooling** - PostgresClient handles this perfectly
❌ **Don't change test patterns** - Suite-level dependencies work well
❌ **Don't add complexity** - Keep the simple test usage patterns

## Implementation Phases

### Phase 1: Foundation (1-2 hours)

**Goal**: Add dependency and make TestDatabase conform to PoolableResource

#### 1.1 Add swift-resource-pool Dependency

**File**: `Package.swift`

```swift
dependencies: [
    // Existing dependencies...
    .package(url: "https://github.com/coenttb/swift-resource-pool", from: "0.1.0")
]

targets: [
    .target(
        name: "RecordsTestSupport",
        dependencies: [
            "Records",
            .product(name: "ResourcePool", package: "swift-resource-pool")
        ]
    )
]
```

#### 1.2 Create PoolableResource Conformance

**File**: `Sources/RecordsTestSupport/TestDatabase+PoolableResource.swift` (new)

```swift
import Foundation
import ResourcePool
@testable import Records

extension Database.TestDatabase: PoolableResource {
    public struct Config: Sendable {
        let setupMode: Database.TestDatabaseSetupMode
        let configuration: PostgresClient.Configuration?
        let prefix: String

        public init(
            setupMode: Database.TestDatabaseSetupMode,
            configuration: PostgresClient.Configuration? = nil,
            prefix: String = "test"
        ) {
            self.setupMode = setupMode
            self.configuration = configuration
            self.prefix = prefix
        }
    }

    public static func create(config: Config) async throws -> Database.TestDatabase {
        // Create database with isolated schema
        let database = try await Database.testDatabase(
            configuration: config.configuration,
            prefix: config.prefix
        )

        // Setup schema based on mode
        switch config.setupMode {
        case .empty:
            break
        case .withSchema:
            try await database.createTestSchema()
        case .withSampleData:
            try await database.createTestSchema()
            try await database.insertSampleData()
        case .withReminderSchema:
            try await database.createReminderSchema()
        case .withReminderData:
            try await database.createReminderSchema()
            try await database.insertReminderSampleData()
        }

        return database
    }

    public func validate() async -> Bool {
        // Check that connection is alive
        do {
            try await self.read { db in
                try await db.execute("SELECT 1")
            }
            return true
        } catch {
            return false
        }
    }

    public func reset() async throws {
        // For test databases, validation is enough
        // We don't need to clean tables since each test uses isolated schemas
        // But we could add table truncation here if needed for shared-schema tests
    }
}
```

**Success Criteria**:
- ✅ Package builds successfully
- ✅ TestDatabase conforms to PoolableResource
- ✅ Can create a basic ResourcePool<TestDatabase>

---

### Phase 2: Enhanced LazyTestDatabase (2-3 hours)

**Goal**: Replace DatabaseManager with ResourcePool while maintaining current API

#### 2.1 Update LazyTestDatabase Implementation

**File**: `Sources/RecordsTestSupport/TestDatabaseHelper.swift`

Replace the current `LazyTestDatabase` implementation:

```swift
import Foundation
import ResourcePool
import Dependencies
@testable import Records

/// A wrapper that provides test databases via ResourcePool
public final class LazyTestDatabase: Database.Writer, @unchecked Sendable {
    private let pool: ResourcePool<Database.TestDatabase>

    enum SetupMode {
        case empty
        case withSchema
        case withSampleData
        case withReminderSchema
        case withReminderData

        var databaseSetupMode: Database.TestDatabaseSetupMode {
            switch self {
            case .empty: return .empty
            case .withSchema: return .withSchema
            case .withSampleData: return .withSampleData
            case .withReminderSchema: return .withReminderSchema
            case .withReminderData: return .withReminderData
            }
        }
    }

    init(
        setupMode: SetupMode,
        capacity: Int = 1,  // Default to 1 for suite-level usage
        warmup: Bool = true
    ) async throws {
        self.pool = try await ResourcePool(
            capacity: capacity,
            resourceConfig: Database.TestDatabase.Config(
                setupMode: setupMode.databaseSetupMode,
                configuration: nil,
                prefix: "test"
            ),
            warmup: warmup
        )
    }

    public func read<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await pool.withResource(timeout: .seconds(30)) { database in
            try await database.read(block)
        }
    }

    public func write<T: Sendable>(
        _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
    ) async throws -> T {
        try await pool.withResource(timeout: .seconds(30)) { database in
            try await database.write(block)
        }
    }

    public func close() async throws {
        try await pool.drain(timeout: .seconds(30))
        await pool.close()
    }

    /// Get pool statistics for debugging
    public var statistics: ResourcePool<Database.TestDatabase>.Statistics {
        get async {
            await pool.statistics
        }
    }

    /// Get pool metrics for observability
    public var metrics: ResourcePool<Database.TestDatabase>.Metrics {
        get async {
            await pool.metrics
        }
    }
}
```

#### 2.2 Update Factory Methods

**File**: `Sources/RecordsTestSupport/TestDatabaseHelper.swift`

```swift
extension Database.TestDatabase {
    /// Creates a test database with User/Post schema
    public static func withSchema() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withSchema,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with User/Post schema and sample data
    public static func withSampleData() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withSampleData,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with Reminder schema (matches upstream)
    public static func withReminderSchema() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withReminderSchema,
            capacity: 1,
            warmup: true
        )
    }

    /// Creates a test database with Reminder schema and sample data (matches upstream)
    public static func withReminderData() async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 1,
            warmup: true
        )
    }
}
```

**Breaking Change**: Factory methods now `async throws` instead of synchronous

**Migration needed**: Update test suite declarations (see Phase 3)

**Success Criteria**:
- ✅ LazyTestDatabase uses ResourcePool internally
- ✅ Same external API (read/write methods)
- ✅ Factory methods compile (now async)

---

### Phase 3: Test Migration (2-3 hours)

**Goal**: Update test suites to use new async factory methods

#### 3.1 Update Test Suite Patterns

**Before**:
```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        // Test code
    }
}
```

**After**:
```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, try await Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func myTest() async throws {
        // Test code unchanged
    }
}
```

**Alternative** (if .dependency doesn't support async):

Create a helper that initializes lazily:

```swift
extension Database.TestDatabase {
    /// Lazy wrapper for dependency injection
    public static func lazyWithReminderData() -> LazyTestDatabase {
        // This won't work - we need async init
        // May need to keep current synchronous pattern with different internal impl
    }
}
```

**Decision Point**: Check if Swift Testing's `.dependency` trait supports async initialization. If not, we may need to:
1. Keep synchronous factory methods
2. Use a different initialization approach
3. Initialize in a suite-level `init()` or setup method

#### 3.2 Files to Update

Update all test files currently using factory methods:

1. `Tests/RecordsTests/SelectExecutionTests.swift`
2. `Tests/RecordsTests/InsertExecutionTests.swift`
3. `Tests/RecordsTests/DeleteExecutionTests.swift`
4. `Tests/RecordsTests/Postgres/ExecutionUpdateTests.swift`
5. `Tests/RecordsTests/IntegrationTests.swift`
6. `Tests/RecordsTests/TransactionTests.swift`
7. `Tests/RecordsTests/DatabaseAccessTests.swift`

**Success Criteria**:
- ✅ All tests compile
- ✅ All tests pass individually
- ✅ All tests pass with cmd+U (parallel execution)

---

### Phase 4: Observability & Metrics (1-2 hours)

**Goal**: Add logging and metrics to monitor pool behavior

#### 4.1 Create Test Helper for Metrics

**File**: `Sources/RecordsTestSupport/TestMetrics.swift` (new)

```swift
import Foundation
import ResourcePool
import Logging

extension LazyTestDatabase {
    /// Log current pool statistics
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
          Avg Wait Time: \(metrics.averageWaitTime?.formatted() ?? "N/A")
          Current Available: \(stats.available)
          Current Leased: \(stats.leased)
        """)
    }
}
```

#### 4.2 Add Metrics to Critical Tests

Add metrics logging to a few test suites to validate behavior:

```swift
@Suite(
    "SELECT Execution Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, try await Database.TestDatabase.withReminderData())
)
struct SelectExecutionTests {
    @Dependency(\.defaultDatabase) var db

    @Test func selectAll() async throws {
        // Before test
        if let lazy = db as? LazyTestDatabase {
            await lazy.logStatistics(label: "SelectTests.Before")
        }

        let reminders = try await db.read { db in
            try await Reminder.all.fetchAll(db)
        }
        #expect(reminders.count == 6)

        // After test
        if let lazy = db as? LazyTestDatabase {
            await lazy.logStatistics(label: "SelectTests.After")
        }
    }
}
```

**Success Criteria**:
- ✅ Can log statistics during test runs
- ✅ Can observe handoff rates (should be 0-10% for suite-level pools)
- ✅ Can track wait times (should be near-zero for single capacity pools)

---

### Phase 5: Advanced Features (Optional, 2-3 hours)

**Goal**: Leverage ResourcePool features for advanced use cases

#### 5.1 Multi-Capacity Pools for Parallel Tests

For test suites that run many tests in parallel, use higher capacity:

```swift
extension Database.TestDatabase {
    /// Creates a pooled test database for parallel test execution
    public static func withReminderDataPooled(capacity: Int = 5) async throws -> LazyTestDatabase {
        try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: capacity,  // Multiple databases!
            warmup: true
        )
    }
}

// Usage in a suite with many parallel tests
@Suite(
    "Heavy Parallel Tests",
    .dependency(\.envVars, .development),
    .dependency(\.defaultDatabase, try await Database.TestDatabase.withReminderDataPooled(capacity: 5))
)
struct HeavyParallelTests {
    // 100 tests can share 5 databases efficiently
    @Test(arguments: 1...100)
    func parallelTest(id: Int) async throws {
        @Dependency(\.defaultDatabase) var db
        // Test operations
    }
}
```

#### 5.2 Resource Cycling for Long-Running Tests

Add resource cycling to prevent connection staleness:

```swift
try await LazyTestDatabase(
    setupMode: .withReminderData,
    capacity: 5,
    warmup: true,
    maxUsesBeforeCycling: 100  // Refresh database after 100 uses
)
```

#### 5.3 Custom Timeouts

For slow operations, adjust timeouts:

```swift
// In LazyTestDatabase, make timeout configurable
public func read<T: Sendable>(
    timeout: Duration = .seconds(30),
    _ block: @Sendable (any Database.Connection.`Protocol`) async throws -> T
) async throws -> T {
    try await pool.withResource(timeout: timeout) { database in
        try await database.read(block)
    }
}

// Usage
try await db.read(timeout: .seconds(60)) { db in
    try await longRunningQuery(db)
}
```

**Success Criteria**:
- ✅ Can configure pool capacity per suite
- ✅ Can enable resource cycling
- ✅ Can customize timeouts

---

## Migration Strategy

### Compatibility Approach

**Option 1: Breaking Change** (Recommended if acceptable)
- Update all factory methods to `async throws`
- Requires updating all test suites
- Clean, modern API
- Leverages ResourcePool fully

**Option 2: Non-Breaking** (If backward compatibility needed)
- Keep synchronous factory methods
- Initialize ResourcePool lazily on first use
- More complex implementation
- Delayed warmup benefits

### Recommended: Option 1 (Breaking Change)

1. Update factory methods to async
2. Update all test suites in one commit
3. Add migration guide to CHANGELOG

**Migration guide**:
```
# Breaking Changes in 0.0.2

## Test Database Factory Methods Now Async

**Before**:
```swift
.dependency(\.defaultDatabase, Database.TestDatabase.withReminderData())
```

**After**:
```swift
.dependency(\.defaultDatabase, try await Database.TestDatabase.withReminderData())
```

**Rationale**: Integration with swift-resource-pool requires async initialization
for proper pre-warming and connection pool setup.
```

---

## Testing Strategy

### Test Levels

1. **Unit Tests**: ResourcePool conformance
   - Test PoolableResource implementation
   - Validate create/validate/reset methods
   - Test error handling

2. **Integration Tests**: LazyTestDatabase behavior
   - Test pool acquisition
   - Test concurrent access
   - Test timeout handling
   - Test cleanup

3. **System Tests**: Full test suite runs
   - Run all existing tests
   - Verify cmd+U still passes
   - Check for regressions
   - Monitor metrics

### Validation Tests

Create specific tests to validate ResourcePool benefits:

**File**: `Tests/RecordsTests/ResourcePoolIntegrationTests.swift` (new)

```swift
import Testing
import RecordsTestSupport
import Dependencies

@Suite("ResourcePool Integration Tests")
struct ResourcePoolIntegrationTests {

    @Test("Pool provides databases under capacity")
    func poolCapacity() async throws {
        let pool = try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 3,
            warmup: true
        )

        let stats = await pool.statistics
        #expect(stats.capacity == 3)
        #expect(stats.totalCreated <= 3)
    }

    @Test("Pool handles concurrent requests")
    func concurrentRequests() async throws {
        let pool = try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 2,
            warmup: true
        )

        // 10 concurrent reads with pool of 2
        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 1...10 {
                group.addTask {
                    try await pool.read { db in
                        let reminders = try await Reminder.all.fetchAll(db)
                        return reminders.count
                    }
                }
            }

            var totalCount = 0
            for try await count in group {
                totalCount += count
            }

            #expect(totalCount == 60)  // 10 reads × 6 reminders
        }

        let metrics = await pool.metrics
        #expect(metrics.totalAcquisitions == 10)
        #expect(metrics.timeouts == 0)
    }

    @Test("Pool warmup creates resources")
    func warmup() async throws {
        let pool = try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 5,
            warmup: true
        )

        // Give warmup time to complete
        try await Task.sleep(for: .seconds(2))

        let stats = await pool.statistics
        #expect(stats.available > 0)  // Should have pre-created resources
    }

    @Test("Pool metrics track handoff rate")
    func handoffRate() async throws {
        let pool = try await LazyTestDatabase(
            setupMode: .withReminderData,
            capacity: 1,
            warmup: true
        )

        // Create contention by sequential requests
        for _ in 1...5 {
            try await pool.read { db in
                try await Reminder.all.fetchAll(db)
            }
        }

        let metrics = await pool.metrics
        await pool.logMetrics(label: "HandoffTest")

        // Should have some handoffs since we're reusing the same database
        #expect(metrics.successfulReturns > 0)
    }
}
```

---

## Success Criteria

### Must Have ✅

1. **Functionality**
   - ✅ All existing tests pass
   - ✅ cmd+U (parallel execution) works
   - ✅ No regressions in test reliability
   - ✅ Pool correctly manages test databases

2. **Performance**
   - ✅ Test execution time unchanged or improved
   - ✅ Pre-warming reduces cold start time
   - ✅ No connection exhaustion

3. **Observability**
   - ✅ Can log pool statistics
   - ✅ Can track handoff rates
   - ✅ Can monitor wait times

### Nice to Have 🎯

1. **Advanced Features**
   - 🎯 Resource cycling for long-running tests
   - 🎯 Configurable timeouts per test
   - 🎯 Multi-capacity pools for heavy parallelism

2. **Documentation**
   - 🎯 Migration guide
   - 🎯 Best practices for test database usage
   - 🎯 Troubleshooting guide with metrics

---

## Rollback Plan

If integration causes issues:

### Quick Rollback (< 1 hour)

1. Revert to commit before integration
2. Restore previous `LazyTestDatabase` implementation
3. Restore synchronous factory methods

### Partial Rollback (1-2 hours)

1. Keep ResourcePool dependency
2. Make it optional (feature flag)
3. Allow tests to use either implementation

### Files to Backup

- `Sources/RecordsTestSupport/TestDatabaseHelper.swift`
- `Sources/RecordsTestSupport/TestDatabasePool.swift`
- All test files using factory methods

---

## Timeline

### Estimated Effort: 8-13 hours

| Phase | Time | Risk |
|-------|------|------|
| Phase 1: Foundation | 1-2h | Low |
| Phase 2: LazyTestDatabase | 2-3h | Medium |
| Phase 3: Test Migration | 2-3h | Low |
| Phase 4: Observability | 1-2h | Low |
| Phase 5: Advanced (Optional) | 2-3h | Low |

### Recommended Schedule

**Day 1** (4-5 hours):
- Phase 1: Add dependency and conformance
- Phase 2: Update LazyTestDatabase
- Checkpoint: Verify compilation

**Day 2** (3-4 hours):
- Phase 3: Migrate tests
- Verify all tests pass
- Checkpoint: cmd+U passes

**Day 3** (2-3 hours):
- Phase 4: Add observability
- Phase 5 (Optional): Advanced features
- Documentation updates

---

## Benefits Summary

### Immediate Benefits

1. **Better Thundering Herd Prevention**
   - Current: Simple `Task.detached` pre-warming
   - New: Coordinated warmup with direct handoff

2. **FIFO Fairness**
   - Current: Undefined wait order
   - New: Tests served in arrival order

3. **Observability**
   - Current: No visibility into pool behavior
   - New: Comprehensive metrics (wait times, handoffs, utilization)

### Long-Term Benefits

1. **Scalability**
   - Proven to 200+ concurrent waiters
   - Can increase capacity for heavy parallel tests

2. **Reliability**
   - Resource validation detects broken databases
   - Resource cycling prevents connection staleness
   - Timeout handling prevents hanging tests

3. **Debugging**
   - Metrics help diagnose test issues
   - Can track performance regressions
   - Handoff rate shows pool efficiency

---

## Questions to Resolve

1. **Does Swift Testing support async in .dependency trait?**
   - If no, need alternative initialization approach
   - May need to wrap in synchronous factory

2. **What pool capacity for different test suites?**
   - Single-test suites: capacity = 1
   - Parallel test suites: capacity = 5-10?
   - Need to balance resources vs speed

3. **Should we replace TestDatabasePool entirely?**
   - Current: Simple actor-based pool
   - Proposed: Keep for backward compatibility or remove?

4. **Metrics logging level?**
   - Debug only?
   - Always enabled with environment flag?
   - Test-specific logging?

---

## Next Steps

1. **Review this plan** with team/stakeholders
2. **Resolve open questions** (Swift Testing async support)
3. **Create feature branch** `feature/resource-pool-integration`
4. **Start Phase 1** (add dependency + conformance)
5. **Checkpoint after each phase** (commit + verify tests)
6. **Document findings** in this plan as we progress

---

## References

- [swift-resource-pool README](https://github.com/coenttb/swift-resource-pool/blob/main/README.md)
- [PARALLEL_TEST_DEBUGGING.md](./PARALLEL_TEST_DEBUGGING.md) - Current solution
- [ResourcePool.swift](https://github.com/coenttb/swift-resource-pool/blob/main/Sources/ResourcePool/ResourcePool.swift) - Implementation
- ResourcePool Tests - Usage examples
