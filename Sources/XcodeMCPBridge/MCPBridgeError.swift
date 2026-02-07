//
//  MCPBridgeError.swift
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

import Foundation

/// Errors that can occur during MCP Bridge operations.
public enum MCPBridgeError: LocalizedError, Equatable, Sendable {
    /// The CLI binary was not found in the app bundle's Resources.
    case bundledBinaryNotFound
    /// Installation of the CLI binary failed.
    case installFailed(String)
    /// Uninstallation of the CLI binary failed.
    case uninstallFailed(String)
    /// The CLI binary is not installed.
    case notInstalled
    /// The bridge is not connected.
    case notConnected
    /// The bridge was disconnected unexpectedly.
    case disconnected
    /// An unexpected response was received from the CLI.
    case unexpectedResponse
    /// Failed to encode a command for the CLI.
    case encodingFailed
    /// The MCP server returned an error.
    case serverError(String)
    /// The CLI binary was not found at the expected install path.
    case cliNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .bundledBinaryNotFound:
            return "Bundled CLI binary not found in app resources"
        case .installFailed(let msg):
            return "Failed to install CLI: \(msg)"
        case .uninstallFailed(let msg):
            return "Failed to uninstall CLI: \(msg)"
        case .notInstalled:
            return "CLI binary is not installed"
        case .notConnected:
            return "Not connected to MCP bridge"
        case .disconnected:
            return "Disconnected from MCP bridge"
        case .unexpectedResponse:
            return "Unexpected response from CLI"
        case .encodingFailed:
            return "Failed to encode command"
        case .serverError(let msg):
            return msg
        case .cliNotFound(let path):
            return "CLI binary not found at: \(path)"
        }
    }

    public static func == (lhs: MCPBridgeError, rhs: MCPBridgeError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
