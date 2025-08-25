# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1] - 2024-01-XX

### Added
- Initial release
- High-level database abstraction layer for PostgreSQL
- Connection pooling with automatic lifecycle management
- Transaction support with isolation levels and savepoints
- Migration system with version tracking
- Testing utilities with schema isolation for parallel test execution
- Actor-based concurrency with Database.Reader and Database.Writer
- Dependency injection support via swift-dependencies
- Full integration with StructuredQueries for type-safe queries
- Environment variable configuration support
- Comprehensive test support module (RecordsTestSupport)

### Features
- **Connection Management**
  - Configurable connection pooling (min/max connections)
  - Automatic connection validation and recovery
  - Graceful shutdown handling
  
- **Query Execution**
  - Type-safe query building via StructuredQueries @Table macro
  - Support for SELECT, INSERT, UPDATE, DELETE operations
  - JOIN, GROUP BY, and aggregate function support
  - Raw SQL execution when needed
  
- **Transaction Support**
  - Multiple isolation levels (READ COMMITTED, SERIALIZABLE, etc.)
  - Nested transactions via savepoints
  - Automatic rollback on errors
  
- **Testing**
  - Schema isolation for parallel test execution
  - Test database pool management
  - Transaction rollback utilities for test isolation
  - Integration with Swift Testing framework

### Dependencies
- swift-structured-queries (0.13.0+)
- swift-structured-queries-postgres (0.2.0+)
- postgres-nio (1.21.0+)
- swift-dependencies (1.9.0+)
- swift-environment-variables (0.0.1+)

### License
- Apache 2.0 License with Runtime Library Exception

### Notes
- This package was extracted from swift-structured-queries-postgres to provide a clean separation between low-level utilities and high-level database operations
- Designed for production use with comprehensive testing support
- Swift 6.0 strict concurrency mode enabled