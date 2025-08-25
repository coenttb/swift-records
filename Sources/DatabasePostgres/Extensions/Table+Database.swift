import StructuredQueries
import StructuredQueriesPostgres

// MARK: - Extensions for SelectStatement with nothing selected

extension SelectStatement where QueryValue == (), Joins == () {
    /// Returns an array of all values fetched from the database.
    ///
    /// This extension enables the pattern: `User.all.fetchAll(db)`
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all values decoded from the database.
    @inlinable
    public func fetchAll(_ db: any DatabaseProtocol) async throws -> [From.QueryOutput] 
    where From: QueryRepresentable {
        // Use selectStar() to select all columns from the From table
        // This returns Select<From, From, ()> where QueryValue = From
        let query = self.selectStar()
        return try await query.fetchAll(db)
    }
    
    /// Returns a single value fetched from the database.
    ///
    /// This extension enables the pattern: `User.all.fetchOne(db)`
    ///
    /// - Parameter db: A database connection.
    /// - Returns: A single value decoded from the database.
    @inlinable
    public func fetchOne(_ db: any DatabaseProtocol) async throws -> From.QueryOutput?
    where From: QueryRepresentable {
        // Use selectStar() to select all columns from the From table
        let query = self.selectStar().limit(1)
        return try await query.fetchOne(db)
    }
}

// MARK: - Table Extensions for static convenience methods

extension Table where Self: QueryRepresentable, Self.QueryOutput == Self {
    /// Fetches all records from the table.
    ///
    /// For example:
    /// ```swift
    /// let users = try await User.fetchAll(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all records in the table.
    @inlinable
    public static func fetchAll(_ db: any DatabaseProtocol) async throws -> [Self] {
        // Use selectStar() to select all columns from the table
        // This matches the pattern used in SharingGRDB
        let query = Self.all.selectStar()
        return try await query.fetchAll(db)
    }
    
    /// Fetches the first record from the table.
    ///
    /// For example:
    /// ```swift
    /// let user = try await User.fetchOne(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The first record in the table, or nil if empty.
    @inlinable
    public static func fetchOne(_ db: any DatabaseProtocol) async throws -> Self? {
        // Use selectStar() and limit to 1
        let query = Self.all.selectStar().limit(1)
        return try await query.fetchOne(db)
    }
    
    /// Returns the number of records in the table.
    ///
    /// For example:
    /// ```swift
    /// let count = try await User.fetchCount(db)
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The number of records in the table.
    @inlinable
    public static func fetchCount(_ db: any DatabaseProtocol) async throws -> Int {
        // Use the existing fetchCount extension on SelectStatement
        try await Self.all.asSelect().fetchCount(db)
    }
}