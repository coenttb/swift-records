import StructuredQueriesPostgres

extension Statement {
    /// Executes a structured query on the given database connection.
    ///
    /// For example:
    ///
    /// ```swift
    /// try await database.write { db in
    ///   try Player.insert { $0.name } values: { "Arthur" }
    ///     .execute(db)
    ///   // INSERT INTO "players" ("name")
    ///   // VALUES ('Arthur');
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    @inlinable
    public func execute(_ db: any Database.Connection.`Protocol`) async throws where QueryValue == () {
        try await db.execute(self)
    }

    /// Returns an array of all values fetched from the database.
    ///
    /// For example:
    ///
    /// ```swift
    /// let players = try await database.read { db in
    ///   let lastName = "O'Reilly"
    ///   try Player
    ///     .where { $0.lastName == lastName }
    ///     .fetchAll(db)
    ///   // SELECT … FROM "players"
    ///   // WHERE "players"."lastName" = 'O''Reilly'
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all values decoded from the database.
    @inlinable
    public func fetchAll(
        _ db: any Database.Connection.`Protocol`
    ) async throws -> [QueryValue.QueryOutput]
    where QueryValue: QueryRepresentable {
        try await db.fetchAll(self)
    }

    /// Returns a single value fetched from the database.
    ///
    /// For example:
    ///
    /// ```swift
    /// let player = try await database.read { db in
    ///   let lastName = "O'Reilly"
    ///   try Player
    ///     .where { $0.lastName == lastName }
    ///     .limit(1)
    ///     .fetchOne(db)
    ///   // SELECT … FROM "players"
    ///   // WHERE "players"."lastName" = 'O''Reilly'
    ///   // LIMIT 1
    /// }
    /// ```
    ///
    /// - Parameter db: A database connection.
    /// - Returns: A single value decoded from the database.
    @inlinable
    public func fetchOne(_ db: any Database.Connection.`Protocol`) async throws -> QueryValue.QueryOutput?
    where QueryValue: QueryRepresentable {
        try await db.fetchOne(self)
    }
}

extension SelectStatement where QueryValue == (), Joins == () {
    /// Returns the number of rows fetched by the query.
    ///
    /// - Parameter db: A database connection.
    /// - Returns: The number of rows fetched by the query.
    @inlinable
    public func fetchCount(_ db: any Database.Connection.`Protocol`) async throws -> Int {
        let query = asSelect().select { _ in .count() }
        return try await query.fetchOne(db) ?? 0
    }
}

extension SelectStatement where QueryValue == (), Joins == () {
    /// Returns an array of all values fetched from the database.
    ///
    /// This extension enables the pattern: `User.all.fetchAll(db)`
    ///
    /// - Parameter db: A database connection.
    /// - Returns: An array of all values decoded from the database.
    @inlinable
    public func fetchAll(_ db: any Database.Connection.`Protocol`) async throws -> [From.QueryOutput]
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
    public func fetchOne(_ db: any Database.Connection.`Protocol`) async throws -> From.QueryOutput?
    where From: QueryRepresentable {
        // Use selectStar() to select all columns from the From table
        let query = self.selectStar().limit(1)
        return try await query.fetchOne(db)
    }
}
