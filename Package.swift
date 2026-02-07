// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XcodeMCPBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XcodeMCPBridge", targets: ["XcodeMCPBridge"]),
        .executable(name: "mcpbridge-cli", targets: ["MCPBridgeCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.17.0"),
    ],
    targets: [
        .target(
            name: "MCPBridgeShared",
            path: "Sources/MCPBridgeShared"
        ),
        .executableTarget(
            name: "MCPBridgeCLI",
            dependencies: ["MCPBridgeShared"],
            path: "Sources/MCPBridgeCLI"
        ),
        .target(
            name: "XcodeMCPBridge",
            dependencies: [
                "MCPBridgeShared",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            path: "Sources/XcodeMCPBridge"
        ),
    ]
)
