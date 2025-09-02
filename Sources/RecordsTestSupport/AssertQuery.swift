//import Dependencies
//import Foundation
//import InlineSnapshotTesting
//import Records
//import StructuredQueriesPostgres
//import StructuredQueriesPostgresTestSupport
//
//// MARK: - Main assertQuery for single QueryRepresentable
//
///// Asserts both SQL generation and database execution for a statement with a single query value.
/////
///// This async wrapper fetches data from the database and then calls the sync assertQuery.
////public func assertQuery<each V: QueryRepresentable & Sendable, S: Statement<(repeat each V)> & Sendable> (
////    _ query: S,
////    execute: (S) throws -> [(repeat (each V).QueryOutput)],
////    sql: (() -> String)? = nil,
////    results: (() -> String)? = nil,
////    snapshotTrailingClosureOffset: Int = 1,
////    fileID: StaticString = #fileID,
////    filePath: StaticString = #filePath,
////    function: StaticString = #function,
////    line: UInt = #line,
////    column: UInt = #column
////) async throws where repeat (each V).QueryOutput: Sendable {
////    @Dependency(\.defaultDatabase) var database
////       
////    let rows: [(repeat (each V).QueryOutput)] = try await database.read { db in
////        try await db.fetchAll(query)
//////        try await db
//////            .execute("\(query)")
//////        db.execute(query.queryFragment.sql)
//////        fatalError()
////    }
////    
////    // Call the synchronous assertQuery from StructuredQueriesPostgresTestSupport
////    StructuredQueriesPostgresTestSupport.assertQuery(
////        query,
////        execute: { _ in rows },
////        sql: sql,
////        results: results,
////        snapshotTrailingClosureOffset: 0,
////        fileID: fileID,
////        filePath: filePath,
////        function: function,
////        line: line,
////        column: column
////    )
////}
//
//
//public func assertQuery<S: Statement>(
//    _ statement: S,
//    sql: (() -> String)? = nil,
//    results: (() -> String)? = nil,
//    fileID: StaticString = #fileID,
//    filePath: StaticString = #filePath,
//    function: StaticString = #function,
//    line: UInt = #line,
//    column: UInt = #column
//) async throws
//where S: Sendable, S.QueryValue: QueryRepresentable, S.QueryValue.QueryOutput: Sendable {
//    @Dependency(\.defaultDatabase) var database
//
//    let rows = try await database.read { db in
//        try await db.fetchAll(statement)
//    }
//
//    var table = ""
//    StructuredQueriesPostgresTestSupport.printTable(rows, to: &table)
//
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
//
//    if !table.isEmpty || results != nil {
//        assertInlineSnapshot(
//            of: table,
//            as: .lines,
//            message: "Results did not match",
//            syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
//                trailingClosureLabel: "results",
//                trailingClosureOffset: 1
//            ),
//            matches: results,
//            fileID: fileID,
//            file: filePath,
//            function: function,
//            line: line,
//            column: column
//        )
//    }
//}
