// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-records",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Records",
            targets: ["Records"]
        ),
        .library(
            name: "RecordsTestSupport",
            targets: ["RecordsTestSupport"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/coenttb/swift-structured-queries-postgres",
            from: "0.0.1",
            traits: ["StructuredQueriesPostgresTagged"]
        ),
        .package(url: "https://github.com/vapor/postgres-nio", from: "1.21.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.10.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.6"),
        .package(url: "https://github.com/coenttb/swift-environment-variables", from: "0.0.1"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Records",
            dependencies: [
                .product(name: "StructuredQueriesPostgres", package: "swift-structured-queries-postgres"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "EnvironmentVariables", package: "swift-environment-variables"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay")
            ]
        ),
        .target(
            name: "RecordsTestSupport",
            dependencies: [
                "Records",
                .product(name: "StructuredQueriesPostgres", package: "swift-structured-queries-postgres"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "StructuredQueriesPostgresTestSupport", package: "swift-structured-queries-postgres"),
            ]
        ),
        .testTarget(
            name: "RecordsTests",
            dependencies: [
                "Records",
                "RecordsTestSupport",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("MemberImportVisibility")
]

for index in package.targets.indices {
    package.targets[index].swiftSettings = swiftSettings
}
