//import Records
//import Dependencies
//import InlineSnapshotTesting
//import StructuredQueriesPostgres
//import StructuredQueriesTestSupport  // For .sql snapshot strategy
//
//// Simple SQL validation helper
//func assertSQL(
//    _ statement: some Statement,
//    matches sql: (() -> String)? = nil,
//    fileID: StaticString = #fileID,
//    filePath: StaticString = #filePath,
//    function: StaticString = #function,
//    line: UInt = #line,
//    column: UInt = #column
//) {
//    assertInlineSnapshot(
//        of: statement,
//        as: .sql,
//        message: "SQL did not match",
//        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
//            trailingClosureLabel: "sql",
//            trailingClosureOffset: 0
//        ),
//        matches: sql,
//        fileID: fileID,
//        file: filePath,
//        function: function,
//        line: line,
//        column: column
//    )
//}
//
//// For testing void statements (INSERT/UPDATE/DELETE without RETURNING)
//func assertExecute(
//    _ statement: some Statement<()> & Sendable,
//    sql: (() -> String)? = nil,
//    fileID: StaticString = #fileID,
//    filePath: StaticString = #filePath,
//    function: StaticString = #function,
//    line: UInt = #line,
//    column: UInt = #column
//) async throws {
//    @Dependency(\.defaultDatabase) var database
//    
//    // Validate SQL
//    assertSQL(statement, matches: sql, fileID: fileID, filePath: filePath, 
//              function: function, line: line, column: column)
//    
//    // Execute
//    try await database.write { [statement] db in
//        try await statement.execute(db)
//    }
//}
//
//// For testing simple table queries
//func assertTableQuery<T: Table>(
//    from table: T.Type,
//    where filter: ((T) -> some SQLPredicate)? = nil,
//    sql: (() -> String)? = nil,
//    fileID: StaticString = #fileID,
//    filePath: StaticString = #filePath,
//    function: StaticString = #function,
//    line: UInt = #line,
//    column: UInt = #column
//) async throws -> [T.QueryOutput] {
//    @Dependency(\.defaultDatabase) var database
//    
//    let query = table.all
//    let finalQuery = filter.map { query.filter($0) } ?? query
//    
//    // Validate SQL
//    assertSQL(finalQuery, matches: sql, fileID: fileID, filePath: filePath,
//              function: function, line: line, column: column)
//    
//    // Execute and return results
//    return try await database.read { db in
//        try await finalQuery.fetchAll(db)
//    }
//}
//
//// For cases where we just need to validate SQL without execution
//func assertQuerySQL(
//    _ statement: some Statement,
//    sql: (() -> String)? = nil,
//    fileID: StaticString = #fileID,
//    filePath: StaticString = #filePath,
//    function: StaticString = #function,
//    line: UInt = #line,
//    column: UInt = #column
//) {
//    assertSQL(statement, matches: sql, fileID: fileID, filePath: filePath,
//              function: function, line: line, column: column)
//}
