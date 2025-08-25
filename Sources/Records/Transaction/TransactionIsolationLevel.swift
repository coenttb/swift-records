import Foundation

/// PostgreSQL transaction isolation levels.
///
/// Controls the level of isolation between concurrent transactions.
public enum TransactionIsolationLevel: String, Sendable {
    /// Allows dirty reads, non-repeatable reads, and phantom reads.
    case readUncommitted = "READ UNCOMMITTED"
    
    /// Prevents dirty reads but allows non-repeatable reads and phantom reads.
    case readCommitted = "READ COMMITTED"
    
    /// Prevents dirty reads and non-repeatable reads but allows phantom reads.
    case repeatableRead = "REPEATABLE READ"
    
    /// Prevents dirty reads, non-repeatable reads, and phantom reads.
    case serializable = "SERIALIZABLE"
}