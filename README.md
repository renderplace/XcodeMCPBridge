# XcodeMCPBridge

A Swift Package for integrating with Xcode's MCP (Model Context Protocol) bridge in macOS apps. Built with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture).

## Architecture

```
┌──────────────┐  App Protocol  ┌──────────────┐  MCP JSON-RPC   ┌────────────┐  XPC   ┌───────┐
│   Your App   │ ◄────────────► │ mcpbridge-cli│ ◄─────────────► │ mcpbridge  │ ◄────► │ Xcode │
│  (SwiftUI)   │   stdin/stdout │ (MCP Client) │   stdin/stdout  │ (Apple)    │        │ (IDE) │
└──────────────┘                └──────────────┘                 └────────────┘        └───────┘
```

**Your App** — Any macOS SwiftUI app using this package. Interacts with the bridge through
`MCPBridgeClient` (TCA dependency) or `MCPBridgeFeature` (TCA reducer). Never touches
MCP protocol details directly.

**mcpbridge-cli** — Companion CLI binary shipped with this package. Acts as an MCP client,
communicating with Apple's `xcrun mcpbridge` via JSON-RPC 2.0 over stdio. The package
automatically installs it from your app bundle to a system path.

**mcpbridge (Apple)** — Apple's native MCP server included with Xcode 26+. Bridges MCP
requests to the running Xcode instance via XPC.

## Requirements

- macOS 26.2+
- Swift 5.9+
- Xcode 26.3+ (with `xcrun mcpbridge` support)

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/renderplace/XcodeMCPBridge.git", from: "1.0.0"),
]
```

Or in Xcode: **File → Add Package Dependencies** and enter the repository URL.

### Embedding the CLI Binary

The package includes a companion CLI executable (`mcpbridge-cli`) that bridges your app to `xcrun mcpbridge`. Your app must build and embed this binary.

**In your Xcode project / XcodeGen spec:**

1. Add the `mcpbridge-cli` product as a build-only dependency (no link, no embed):

```yaml
# project.yml (XcodeGen)
packages:
  XcodeMCPBridge:
    url: https://github.com/YOUR_ORG/XcodeMCPBridge.git
    from: "1.0.0"

targets:
  MyApp:
    dependencies:
      - package: XcodeMCPBridge
        product: XcodeMCPBridge
      - package: XcodeMCPBridge
        product: mcpbridge-cli
        embed: false
        link: false
```

2. Add a **Run Script** build phase to copy the CLI into your app bundle:

```bash
mkdir -p "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
cp "${BUILT_PRODUCTS_DIR}/mcpbridge-cli" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/mcpbridge-cli"
chmod 755 "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/mcpbridge-cli"
```

## Quick Start

```swift
import XcodeMCPBridge
import ComposableArchitecture

@Reducer
struct AppFeature {
    struct State {
        var bridge = MCPBridgeFeature.State()
    }

    enum Action {
        case bridge(MCPBridgeFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.bridge, action: \.bridge) {
            MCPBridgeFeature()
        }
    }
}
```

In your view:

```swift
// Connect button
Button("Connect to Xcode") {
    store.send(.bridge(.connectTapped))
}

// Status display
Text(store.bridge.statusText)
```

## Using the Dependency Directly

For more control, use `MCPBridgeClient` as a TCA dependency:

```swift
@Dependency(\.mcpBridgeClient) var mcpBridge

// Install CLI binary
try await mcpBridge.install()

// Connect to Xcode's MCP bridge
let serverInfo = try await mcpBridge.connect()

// List available tools
let tools = try await mcpBridge.listTools()

// Execute a tool
let result = try await mcpBridge.callTool("XcodeBuildProject", ["tabIdentifier": "windowtab1"])

// Check status
let status = mcpBridge.status() // .connected, .executing, etc.

// Disconnect
await mcpBridge.disconnect()

// Uninstall CLI
try await mcpBridge.uninstall()
```

## Configuration

Customize the CLI binary name and install location:

```swift
Store(initialState: AppFeature.State()) {
    AppFeature()
} withDependencies: {
    $0.mcpBridgeClient = .live(
        configuration: MCPBridgeConfiguration(
            cliBinaryName: "my-custom-mcp-cli",
            installDirectory: "/usr/local/bin"
        )
    )
}
```

> **Note:** When using a custom binary name, the Run Script build phase and bundled resource name must match.

## API Reference

### MCPBridgeClient

| Method | Description |
|--------|-------------|
| `install()` | Installs/updates the CLI binary from app bundle to system path |
| `uninstall()` | Removes the installed CLI binary |
| `connect()` | Connects to Xcode's MCP bridge, returns `BridgeServerInfo` |
| `disconnect()` | Disconnects from the bridge |
| `listTools()` | Returns available `[MCPTool]` from Xcode |
| `callTool(_:_:)` | Executes a tool, returns `BridgeToolResult` |
| `status()` | Returns current `MCPBridgeStatus` |

### MCPBridgeStatus

- `.notInstalled` — CLI binary is not installed
- `.installing` — Installation in progress
- `.installed` — Installed but not connected
- `.connecting` — Connection in progress
- `.connected` — Ready to execute tools
- `.executing` — A tool call is in progress

### MCPBridgeFeature (TCA Reducer)

Pre-built reducer handling the full lifecycle. Actions:

- `.installTapped` — Install CLI only
- `.uninstallTapped` — Remove CLI
- `.connectTapped` — Auto-install + connect
- `.disconnectTapped` — Disconnect

State includes `status`, `serverInfo`, `error`, `isConnected`, and `statusText`.

---

> *"Built by a developer, for developers — because the best tools are the ones you'd want to use yourself."* ❤️
>
> — **Anton Gregorn** · [@renderplace](https://x.com/renderplace)

## License

MIT License

Copyright © 2026 Anton Gregorn. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
