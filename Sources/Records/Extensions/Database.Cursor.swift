import Foundation
import StructuredQueries
import StructuredQueriesPostgres

// MARK: - Database.Cursor

extension Database {
    /// A cursor for iterating over query results.
    ///
    /// Query cursors allow you to iterate over database results without loading
    /// all rows into memory at once.
    public struct Cursor<Element: Sendable>: AsyncSequence, Sendable {
        public typealias Element = Element
        
        private let fetchNext: @Sendable () async throws -> Element?
        
        init(fetchNext: @escaping @Sendable () async throws -> Element?) {
            self.fetchNext = fetchNext
        }
        
        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(fetchNext: fetchNext)
        }
        
        public struct AsyncIterator: AsyncIteratorProtocol {
            private let fetchNext: @Sendable () async throws -> Element?
            private var exhausted = false
            
            init(fetchNext: @escaping @Sendable () async throws -> Element?) {
                self.fetchNext = fetchNext
            }
            
            public mutating func next() async throws -> Element? {
                guard !exhausted else { return nil }
                
                if let element = try await fetchNext() {
                    return element
                } else {
                    exhausted = true
                    return nil
                }
            }
        }
        
        /// Returns the next element from the cursor.
        public func next() async throws -> Element? {
            try await fetchNext()
        }
        
        /// Collects all remaining elements into an array.
        ///
        /// - Warning: This loads all remaining rows into memory.
        public func fetchAll() async throws -> [Element] {
            var results: [Element] = []
            while let element = try await next() {
                results.append(element)
            }
            return results
        }
    }
}

// MARK: - Database.Cursor.IteratorManager

extension Database.Cursor {
    /// Actor to safely manage the iterator
    fileprivate actor IteratorManager {
        private var iterator: Array<Element>.Iterator
        
        init(_ array: [Element]) {
            self.iterator = array.makeIterator()
        }
        
        func next() -> Element? {
            iterator.next()
        }
    }
}

// MARK: - Database.Connection.`Protocol` Extension

extension Database.Connection.`Protocol` {
    /// Returns a cursor for the given statement.
    func fetchCursor<QueryValue: QueryRepresentable>(
        _ statement: some Statement<QueryValue>
    ) async throws -> Database.Cursor<QueryValue.QueryOutput> {
        // For now, we'll fetch all results and create a cursor from them
        // This is not ideal for memory usage, but works as a starting point
        let results = try await fetchAll(statement)
        let manager = Database.Cursor<QueryValue.QueryOutput>.IteratorManager(results)
        
        return Database.Cursor<QueryValue.QueryOutput> {
            await manager.next()
        }
    }
}
