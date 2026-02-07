//
//  MCPBridgeConfiguration.swift
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

/// Configuration for the MCP Bridge client.
///
/// Allows customization of the CLI binary name and install location.
///
/// ```swift
/// // Default configuration
/// let config = MCPBridgeConfiguration()
///
/// // Custom binary name
/// let config = MCPBridgeConfiguration(cliBinaryName: "my-mcp-cli")
/// ```
public struct MCPBridgeConfiguration: Sendable, Equatable {
    /// Name of the CLI binary (without path). Default: `"mcpbridge-cli"`.
    public var cliBinaryName: String

    /// Directory where the CLI binary is installed. Default: `"/usr/local/bin"`.
    public var installDirectory: String

    public init(
        cliBinaryName: String = "mcpbridge-cli",
        installDirectory: String = "/usr/local/bin"
    ) {
        self.cliBinaryName = cliBinaryName
        self.installDirectory = installDirectory
    }

    /// Full path to the installed CLI binary.
    public var installPath: String {
        (installDirectory as NSString).appendingPathComponent(cliBinaryName)
    }

    /// URL to the bundled CLI binary in the app's Resources.
    public var bundledCLIURL: URL? {
        Bundle.main.url(forResource: cliBinaryName, withExtension: nil)
    }
}
