//
//  MCPBridgeFeature.swift
//  XcodeMCPBridge
//
//  Created by Anton Gregorn on 7. 2. 26.
//
//  MIT License
//
//  Copyright © 2026 Anton Gregorn. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import ComposableArchitecture
import Foundation
import MCPBridgeShared

/// A TCA reducer managing the MCP Bridge lifecycle:
/// install, connect, disconnect, uninstall, and status tracking.
///
/// Compose into your app feature:
/// ```swift
/// @Reducer
/// struct AppFeature {
///     struct State {
///         var bridge = MCPBridgeFeature.State()
///         // ...
///     }
///     enum Action {
///         case bridge(MCPBridgeFeature.Action)
///         // ...
///     }
///     var body: some ReducerOf<Self> {
///         Scope(state: \.bridge, action: \.bridge) {
///             MCPBridgeFeature()
///         }
///         // ...
///     }
/// }
/// ```
@Reducer
public struct MCPBridgeFeature {
    @ObservableState
    public struct State: Equatable {
        /// Current status of the bridge client.
        public var status: MCPBridgeStatus = .notInstalled
        /// Server info after successful connection.
        public var serverInfo: BridgeServerInfo?
        /// Last error message, if any.
        public var error: String?

        public init(
            status: MCPBridgeStatus = .notInstalled,
            serverInfo: BridgeServerInfo? = nil,
            error: String? = nil
        ) {
            self.status = status
            self.serverInfo = serverInfo
            self.error = error
        }

        /// Whether the bridge is connected and ready.
        public var isConnected: Bool {
            status == .connected || status == .executing
        }

        /// Human-readable status text suitable for display.
        public var statusText: String {
            switch status {
            case .notInstalled: return "Not Installed"
            case .installing: return "Installing…"
            case .installed: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected:
                if let info = serverInfo {
                    return "Connected to \(info.name) \(info.version)"
                }
                return "Connected"
            case .executing: return "Executing…"
            }
        }
    }

    public enum Action {
        /// User-initiated: install the CLI binary.
        case installTapped
        /// User-initiated: uninstall the CLI binary.
        case uninstallTapped
        /// User-initiated: install (if needed) and connect.
        case connectTapped
        /// User-initiated: disconnect from the bridge.
        case disconnectTapped

        // Internal result actions
        case _installResult(Result<Void, Error>)
        case _connectionResult(Result<BridgeServerInfo, Error>)
        case _disconnected
        case _uninstallResult(Result<Void, Error>)
    }

    @Dependency(\.mcpBridgeClient) var client

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .installTapped:
                state.status = .installing
                state.error = nil
                return .run { send in
                    do {
                        try await client.install()
                        await send(._installResult(.success(())))
                    } catch {
                        await send(._installResult(.failure(error)))
                    }
                }

            case ._installResult(.success):
                state.status = .installed
                return .none

            case ._installResult(.failure(let error)):
                state.status = .notInstalled
                state.error = error.localizedDescription
                return .none

            case .uninstallTapped:
                state.error = nil
                return .run { send in
                    do {
                        try await client.uninstall()
                        await send(._uninstallResult(.success(())))
                    } catch {
                        await send(._uninstallResult(.failure(error)))
                    }
                }

            case ._uninstallResult(.success):
                state.status = .notInstalled
                state.serverInfo = nil
                return .none

            case ._uninstallResult(.failure(let error)):
                state.error = error.localizedDescription
                return .none

            case .connectTapped:
                state.error = nil
                state.status = .installing
                // Step 1: Install (or update) the CLI
                return .run { send in
                    do {
                        try await client.install()
                        await send(._installResult(.success(())))
                    } catch {
                        await send(._installResult(.failure(error)))
                        return
                    }
                    // Step 2: Connect
                    do {
                        let info = try await client.connect()
                        await send(._connectionResult(.success(info)))
                    } catch {
                        await send(._connectionResult(.failure(error)))
                    }
                }

            case ._connectionResult(.success(let info)):
                state.status = .connected
                state.serverInfo = info
                state.error = nil
                return .none

            case ._connectionResult(.failure(let error)):
                state.status = .installed
                state.serverInfo = nil
                state.error = error.localizedDescription
                return .none

            case .disconnectTapped:
                return .run { send in
                    await client.disconnect()
                    await send(._disconnected)
                }

            case ._disconnected:
                state.status = .installed
                state.serverInfo = nil
                return .none
            }
        }
    }
}
