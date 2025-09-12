//
//  File.swift
//  database-postgres
//
//  Created by Coen ten Thije Boonkkamp on 25/08/2025.
//

import EnvironmentVariables
import Foundation
import RecordsTestSupport
import Testing

extension URL {
    static var projectRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

// Add EnvironmentVariables configuration
extension EnvironmentVariables {
    static let development: Self = try! .live(environmentConfiguration: .projectRoot(.projectRoot, environment: "development"))
}

@MainActor @Suite(.serialized, .snapshots(record: .failed)) struct SnapshotTests {}
