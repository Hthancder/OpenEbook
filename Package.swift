// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BookReaderCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/readium/ZIPFoundation.git", exact: "3.0.1"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.5")
    ],
    targets: [
        .target(
            name: "BookReaderCore",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "ReadiumZIPFoundation", package: "ZIPFoundation")
            ],
            path: "BookReader",
            sources: [
                "Domain/BookFormat.swift", "Domain/BookFormatRegistry.swift", "Domain/BookRecord.swift",
                "Domain/EPUBMetadata.swift", "Domain/ImportFailure.swift", "Domain/ImportSecurity.swift",
                "Domain/ReadingLocation.swift", "Domain/ReaderBookmark.swift", "Domain/LibrarySortOption.swift",
                "Services/TextDecoder.swift", "Services/EPUBExtractionState.swift", "Services/EPUBArchivePreflight.swift", "Services/EPUBMetadataReader.swift"
            ]
        ),
        .testTarget(
            name: "BookReaderCoreTests",
            dependencies: ["BookReaderCore", .product(name: "SwiftSoup", package: "SwiftSoup"), .product(name: "ReadiumZIPFoundation", package: "ZIPFoundation")],
            path: "BookReaderTests",
            sources: ["CoreTests.swift"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
