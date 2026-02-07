//
//  MCPBridgeClient.swift
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

import Dependencies
import Foundation
import MCPBridgeShared

// MARK: - MCPBridgeClient (TCA Dependency)

/// A TCA dependency providing the full MCP Bridge lifecycle:
/// install, connect, list tools, call tools, disconnect, uninstall.
///
/// Usage in a reducer:
/// ```swift
/// @Dependency(\.mcpBridgeClient) var mcpBridge
///
/// // Install CLI
/// try await mcpBridge.install()
///
/// // Connect to Xcode
/// let serverInfo = try await mcpBridge.connect()
///
/// // List available tools
/// let tools = try await mcpBridge.listTools()
///
/// // Execute a tool
/// let result = try await mcpBridge.callTool("XcodeListWindows", [:])
///
/// // Disconnect
/// await mcpBridge.disconnect()
/// ```
public struct MCPBridgeClient: Sendable {
    /// Installs (or updates) the CLI binary from the app bundle to the system path.
    public var install: @Sendable () async throws -> Void

    /// Removes the installed CLI binary.
    public var uninstall: @Sendable () async throws -> Void

    /// Connects to the Xcode MCP bridge via the installed CLI.
    public var connect: @Sendable () async throws -> BridgeServerInfo

    /// Disconnects from the Xcode MCP bridge.
    public var disconnect: @Sendable () async -> Void

    /// Lists all available MCP tools from the connected Xcode instance.
    public var listTools: @Sendable () async throws -> [MCPTool]

    /// Executes an MCP tool with the given arguments.
    public var callTool: @Sendable (_ name: String, _ arguments: [String: String]) async throws -> BridgeToolResult

    /// Returns the current status of the bridge client.
    public var status: @Sendable () -> MCPBridgeStatus

    public init(
        install: @escaping @Sendable () async throws -> Void,
        uninstall: @escaping @Sendable () async throws -> Void,
        connect: @escaping @Sendable () async throws -> BridgeServerInfo,
        disconnect: @escaping @Sendable () async -> Void,
        listTools: @escaping @Sendable () async throws -> [MCPTool],
        callTool: @escaping @Sendable (_ name: String, _ arguments: [String: String]) async throws -> BridgeToolResult,
        status: @escaping @Sendable () -> MCPBridgeStatus
    ) {
        self.install = install
        self.uninstall = uninstall
        self.connect = connect
        self.disconnect = disconnect
        self.listTools = listTools
        self.callTool = callTool
        self.status = status
    }
}

// MARK: - Factory

extension MCPBridgeClient {
    /// Creates a live ``MCPBridgeClient`` backed by a real CLI process.
    ///
    /// - Parameter configuration: Customizes binary name and install path.
    /// - Returns: A fully configured client ready for use.
    public static func live(
        configuration: MCPBridgeConfiguration = .init()
    ) -> MCPBridgeClient {
        let manager = ProcessManager(configuration: configuration)
        return MCPBridgeClient(
            install: { try manager.installCLI() },
            uninstall: { try manager.uninstallCLI() },
            connect: { try await manager.connect() },
            disconnect: { await manager.disconnect() },
            listTools: { try await manager.listTools() },
            callTool: { name, args in try await manager.callTool(name: name, arguments: args) },
            status: { manager.currentStatus }
        )
    }
}

// MARK: - DependencyKey

extension MCPBridgeClient: DependencyKey {
    public static let liveValue = MCPBridgeClient.live()
}

extension MCPBridgeClient: TestDependencyKey {
    public static let previewValue = MCPBridgeClient(
        install: {},
        uninstall: {},
        connect: {
            BridgeServerInfo(name: "Test Xcode", version: "26.3", protocolVersion: "2024-11-05")
        },
        disconnect: {},
        listTools: {
            [
                MCPTool(name: "BuildProject", description: "Build an Xcode project"),
                MCPTool(name: "DocumentationSearch", description: "Search Apple documentation"),
                MCPTool(name: "RenderPreview", description: "Render a SwiftUI preview"),
            ]
        },
        callTool: { name, _ in
            BridgeToolResult(
                content: [MCPContentItem(type: "text", text: "Mock result for \(name)")],
                isError: false
            )
        },
        status: { .notInstalled }
    )
}

public extension DependencyValues {
    var mcpBridgeClient: MCPBridgeClient {
        get { self[MCPBridgeClient.self] }
        set { self[MCPBridgeClient.self] = newValue }
    }
}

// MARK: - Process Manager (internal)

/// Manages the CLI subprocess lifecycle, command dispatch, and status tracking.
final class ProcessManager: @unchecked Sendable {
    private let configuration: MCPBridgeConfiguration
    private let lock = NSLock()
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var pendingRequests: [String: CheckedContinuation<BridgeResponse, Error>] = [:]
    private var readTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var _status: MCPBridgeStatus = .notInstalled

    init(configuration: MCPBridgeConfiguration) {
        self.configuration = configuration
        // Check initial installation state
        if MCPBridgeInstaller.isInstalled(configuration: configuration) {
            _status = .installed
        }
    }

    var currentStatus: MCPBridgeStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    private func setStatus(_ status: MCPBridgeStatus) {
        lock.lock()
        _status = status
        lock.unlock()
    }

    // MARK: - Install / Uninstall

    func installCLI() throws {
        setStatus(.installing)
        do {
            try MCPBridgeInstaller.install(configuration: configuration)
            setStatus(.installed)
        } catch {
            setStatus(.notInstalled)
            throw error
        }
    }

    func uninstallCLI() throws {
        let wasConnected: Bool = {
            lock.lock()
            defer { lock.unlock() }
            return process?.isRunning ?? false
        }()

        if wasConnected {
            // Synchronous disconnect
            disconnectSync()
        }

        try MCPBridgeInstaller.uninstall(configuration: configuration)
        setStatus(.notInstalled)
    }

    // MARK: - Connect / Disconnect

    func connect() async throws -> BridgeServerInfo {
        disconnectSync()
        setStatus(.connecting)

        let cliPath = configuration.installPath
        guard FileManager.default.fileExists(atPath: cliPath) else {
            setStatus(.notInstalled)
            throw MCPBridgeError.cliNotFound(cliPath)
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cliPath)
        proc.environment = ProcessInfo.processInfo.environment

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            setStatus(.installed)
            throw MCPBridgeError.serverError("Failed to launch CLI: \(error.localizedDescription)")
        }

        lock.lock()
        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        lock.unlock()

        startReading(from: stdout)

        do {
            let response = try await sendCommand(BridgeCommand(action: .connect))
            guard case .connected(let serverInfo) = response.data else {
                setStatus(.installed)
                throw MCPBridgeError.unexpectedResponse
            }
            setStatus(.connected)
            return serverInfo
        } catch {
            disconnectSync()
            setStatus(.installed)
            throw error
        }
    }

    func disconnect() async {
        disconnectSync()
    }

    private func disconnectSync() {
        readTask?.cancel()
        readTask = nil

        lock.lock()
        if let proc = process, proc.isRunning {
            if let stdinPipe {
                let cmd = BridgeCommand(action: .disconnect)
                if let data = try? encoder.encode(cmd),
                   let line = String(data: data, encoding: .utf8)
                {
                    stdinPipe.fileHandleForWriting.write("\(line)\n".data(using: .utf8)!)
                }
            }
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil

        let pending = pendingRequests
        pendingRequests.removeAll()

        let wasConnected = _status == .connected || _status == .executing || _status == .connecting
        if wasConnected {
            _status = MCPBridgeInstaller.isInstalled(configuration: configuration) ? .installed : .notInstalled
        }
        lock.unlock()

        for (_, continuation) in pending {
            continuation.resume(throwing: MCPBridgeError.disconnected)
        }
    }

    // MARK: - Tool Operations

    func listTools() async throws -> [MCPTool] {
        let response = try await sendCommand(BridgeCommand(action: .listTools))

        if let error = response.error {
            throw MCPBridgeError.serverError(error)
        }

        guard case .tools(let tools) = response.data else {
            throw MCPBridgeError.unexpectedResponse
        }
        return tools
    }

    func callTool(name: String, arguments: [String: String]) async throws -> BridgeToolResult {
        let previousStatus = currentStatus
        setStatus(.executing)

        defer { setStatus(previousStatus) }

        let response = try await sendCommand(
            BridgeCommand(action: .callTool(name: name, arguments: arguments))
        )

        if let error = response.error {
            throw MCPBridgeError.serverError(error)
        }

        guard case .toolResult(let result) = response.data else {
            throw MCPBridgeError.unexpectedResponse
        }
        return result
    }

    // MARK: - Command Transport

    private func sendCommand(_ command: BridgeCommand) async throws -> BridgeResponse {
        lock.lock()
        guard let stdinPipe else {
            lock.unlock()
            throw MCPBridgeError.notConnected
        }
        lock.unlock()

        guard let data = try? encoder.encode(command),
              let line = String(data: data, encoding: .utf8)
        else {
            throw MCPBridgeError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pendingRequests[command.id] = continuation
            lock.unlock()

            stdinPipe.fileHandleForWriting.write("\(line)\n".data(using: .utf8)!)
        }
    }

    private func startReading(from pipe: Pipe) {
        readTask = Task { [weak self] in
            let handle = pipe.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let newlineRange = buffer.range(of: Data([UInt8(ascii: "\n")])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                    guard !lineData.isEmpty else { continue }
                    self?.handleResponseLine(lineData)
                }
            }
        }
    }

    private func handleResponseLine(_ data: Data) {
        guard let response = try? decoder.decode(BridgeResponse.self, from: data) else {
            return
        }

        lock.lock()
        if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
            lock.unlock()
            continuation.resume(returning: response)
        } else {
            lock.unlock()
        }
    }
}
