// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.toolbox-client-pure",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library( name: "WhooshingClient", targets: ["WhooshingClient"] ),
    ],
    dependencies: [
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-basic.git", .upToNextMajor(from: "1.2.3")),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.82.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WhooshingClient",
            dependencies: [
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "toolbox-client-Tests",
            dependencies: [
                .target(name: "WhooshingClient"),
            ]
        ),
    ]
)
