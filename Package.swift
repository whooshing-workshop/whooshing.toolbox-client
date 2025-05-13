// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

static func package(url: String, _ range: Range<Version>) -> Package.Dependency {
    return .package(path: "Client")
}

static func package(url: String, branch: String) -> Package.Dependency {
    return .package(path: "Client")
}
