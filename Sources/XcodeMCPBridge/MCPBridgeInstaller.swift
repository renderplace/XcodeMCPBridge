//
//  MCPBridgeInstaller.swift
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

import CryptoKit
import Foundation

/// Manages installation and uninstallation of the MCP Bridge CLI binary.
///
/// The CLI binary is bundled in the app's Resources and installed to a
/// system path (default: `/usr/local/bin/mcpbridge-cli`). Uses SHA-256
/// checksums to detect when an update is needed.
public enum MCPBridgeInstaller {

    /// Ensures the CLI binary is installed and up-to-date.
    ///
    /// - Parameter configuration: The bridge configuration specifying binary name and install path.
    /// - Throws: ``MCPBridgeError/bundledBinaryNotFound`` if the binary is not in app Resources.
    /// - Throws: ``MCPBridgeError/installFailed(_:)`` if installation fails.
    @discardableResult
    public static func install(
        configuration: MCPBridgeConfiguration = .init()
    ) throws -> String {
        guard let bundledURL = configuration.bundledCLIURL else {
            throw MCPBridgeError.bundledBinaryNotFound
        }

        let installPath = configuration.installPath
        let fm = FileManager.default

        if fm.fileExists(atPath: installPath) {
            // Compare SHA-256 checksums — skip if already up-to-date
            let bundledData = try Data(contentsOf: bundledURL)
            let installedData = try Data(contentsOf: URL(fileURLWithPath: installPath))

            let bundledHash = SHA256.hash(data: bundledData)
            let installedHash = SHA256.hash(data: installedData)

            if bundledHash == installedHash {
                return installPath
            }
        }

        try performInstall(from: bundledURL, to: installPath)
        return installPath
    }

    /// Removes the installed CLI binary.
    ///
    /// - Parameter configuration: The bridge configuration specifying binary name and install path.
    /// - Throws: ``MCPBridgeError/uninstallFailed(_:)`` if removal fails.
    public static func uninstall(
        configuration: MCPBridgeConfiguration = .init()
    ) throws {
        let installPath = configuration.installPath
        let fm = FileManager.default

        guard fm.fileExists(atPath: installPath) else {
            return // Already uninstalled
        }

        do {
            try fm.removeItem(atPath: installPath)
        } catch {
            // Try with admin privileges
            try uninstallWithPrivileges(path: installPath)
        }
    }

    /// Checks whether the CLI binary is installed.
    ///
    /// - Parameter configuration: The bridge configuration specifying binary name and install path.
    /// - Returns: `true` if the binary exists at the configured install path.
    public static func isInstalled(
        configuration: MCPBridgeConfiguration = .init()
    ) -> Bool {
        FileManager.default.fileExists(atPath: configuration.installPath)
    }

    // MARK: - Private

    private static func performInstall(from source: URL, to destination: String) throws {
        let fm = FileManager.default
        let dir = (destination as NSString).deletingLastPathComponent

        // Ensure parent directory exists
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                try installWithPrivileges(from: source.path, to: destination)
                return
            }
        }

        // Try direct copy
        do {
            if fm.fileExists(atPath: destination) {
                try fm.removeItem(atPath: destination)
            }
            try fm.copyItem(at: source, to: URL(fileURLWithPath: destination))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
        } catch {
            try installWithPrivileges(from: source.path, to: destination)
        }
    }

    private static func installWithPrivileges(from source: String, to destination: String) throws {
        let dir = (destination as NSString).deletingLastPathComponent
        let shellCommand = "mkdir -p '\(dir)' && cp '\(source)' '\(destination)' && chmod 755 '\(destination)'"
        try runAppleScript("do shell script \"\(shellCommand)\" with administrator privileges",
                           errorType: { MCPBridgeError.installFailed($0) })
    }

    private static func uninstallWithPrivileges(path: String) throws {
        let shellCommand = "rm -f '\(path)'"
        try runAppleScript("do shell script \"\(shellCommand)\" with administrator privileges",
                           errorType: { MCPBridgeError.uninstallFailed($0) })
    }

    private static func runAppleScript(
        _ script: String,
        errorType: (String) -> MCPBridgeError
    ) throws {
        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            throw errorType("Failed to create AppleScript")
        }

        appleScript.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw errorType(msg)
        }
    }
}
