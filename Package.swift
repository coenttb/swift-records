// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "database-postgres",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "DatabasePostgres",
            targets: ["DatabasePostgres"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/coenttb/swift-structured-queries-postgres", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.13.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/coenttb/swift-environment-variables", from: "0.0.1"),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.5.0"),
        .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "DatabasePostgres",
            dependencies: [
                .product(name: "StructuredQueriesPostgres", package: "swift-structured-queries-postgres"),
                .product(name: "StructuredQueries", package: "swift-structured-queries"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "EnvironmentVariables", package: "swift-environment-variables"),
                .product(name: "IssueReporting", package: "xctest-dynamic-overlay")
            ]
        ),
        .testTarget(
            name: "DatabasePostgresTests",
            dependencies: [
                "DatabasePostgres",
                .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
                .product(name: "ConcurrencyExtras", package: "swift-concurrency-extras")
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