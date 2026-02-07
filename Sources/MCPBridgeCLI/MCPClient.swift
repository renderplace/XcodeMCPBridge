//
//  MCPClient.swift
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
import MCPBridgeShared

/// MCP client that communicates with `xcrun mcpbridge` via stdio JSON-RPC 2.0.
actor MCPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var nextId = 1
    private var readTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var isConnected: Bool { process?.isRunning ?? false }

    // MARK: - Lifecycle

    func connect(xcodePID: String? = nil, sessionID: String? = nil) async throws -> MCPInitializeResult {
        guard process == nil else {
            throw MCPError.alreadyConnected
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["mcpbridge"]

        var env = ProcessInfo.processInfo.environment
        if let pid = xcodePID {
            env["MCP_XCODE_PID"] = pid
        }
        if let sid = sessionID {
            env["MCP_XCODE_SESSION_ID"] = sid
        }
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        try proc.run()

        self.process = proc
        self.stdinPipe = stdin
        self.stdoutPipe = stdout

        // Start reading responses from mcpbridge
        startReading(from: stdout)

        // MCP Handshake: initialize
        let initParams = MCPInitializeParams()
        let initResult = try await sendRequest(
            method: "initialize",
            params: initParams
        )

        guard let resultDict = initResult.result?.dictValue else {
            throw MCPError.invalidResponse("Missing initialize result")
        }

        // Send initialized notification (no response expected)
        sendNotification(method: "notifications/initialized")

        // Parse the result
        let resultData = try JSONSerialization.data(withJSONObject: resultDict)
        let parsed = try decoder.decode(MCPInitializeResult.self, from: resultData)
        return parsed
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil

        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: MCPError.disconnected)
        }
        pendingRequests.removeAll()
    }

    // MARK: - MCP Operations

    func listTools() async throws -> [MCPTool] {
        let response = try await sendRequest(method: "tools/list", params: Optional<String>.none)

        guard let resultDict = response.result?.dictValue else {
            throw MCPError.invalidResponse("Missing tools/list result")
        }

        let resultData = try JSONSerialization.data(withJSONObject: resultDict)
        let parsed = try decoder.decode(MCPToolsListResult.self, from: resultData)
        return parsed.tools
    }

    func callTool(name: String, arguments: [String: String]) async throws -> MCPToolCallResult {
        let params = MCPToolCallParams(
            name: name,
            arguments: arguments.isEmpty ? nil : arguments.mapValues { AnyCodable($0) }
        )

        let response = try await sendRequest(method: "tools/call", params: params)

        if let error = response.error {
            throw MCPError.serverError(code: error.code, message: error.message)
        }

        guard let resultDict = response.result?.dictValue else {
            throw MCPError.invalidResponse("Missing tools/call result")
        }

        let resultData = try JSONSerialization.data(withJSONObject: resultDict)
        return try decoder.decode(MCPToolCallResult.self, from: resultData)
    }

    // MARK: - JSON-RPC Transport

    private func sendRequest<P: Encodable>(method: String, params: P?) async throws -> JSONRPCResponse {
        guard let stdinPipe else { throw MCPError.notConnected }

        let reqId = nextId
        nextId += 1

        // Build the JSON-RPC request manually to handle generic params
        var jsonObject: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
        ]

        if let params {
            let paramsData = try encoder.encode(params)
            let paramsValue = try JSONSerialization.jsonObject(with: paramsData)
            jsonObject["params"] = paramsValue
        } else {
            jsonObject["params"] = [String: Any]()
        }

        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        var line = data
        line.append(contentsOf: [UInt8(ascii: "\n")])

        stdinPipe.fileHandleForWriting.write(line)

        // Wait for response with matching id
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[reqId] = continuation
        }
    }

    private func sendNotification(method: String) {
        guard let stdinPipe else { return }

        let jsonObject: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys]) else {
            return
        }
        var line = data
        line.append(contentsOf: [UInt8(ascii: "\n")])
        stdinPipe.fileHandleForWriting.write(line)
    }

    // MARK: - Response Reading

    private func startReading(from pipe: Pipe) {
        readTask = Task { [weak self] in
            let handle = pipe.fileHandleForReading
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    // EOF - process terminated
                    break
                }
                buffer.append(chunk)

                // Process complete lines
                while let newlineRange = buffer.range(of: Data([UInt8(ascii: "\n")])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                    guard !lineData.isEmpty else { continue }

                    await self?.handleResponseLine(lineData)
                }
            }
        }
    }

    private func handleResponseLine(_ data: Data) {
        do {
            let response = try decoder.decode(JSONRPCResponse.self, from: data)

            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
            // Notifications (no id) are ignored for now
        } catch {
            // Log parse errors to stderr (not stdout, which is for app communication)
            let msg = String(data: data, encoding: .utf8) ?? "<binary>"
            FileHandle.standardError.write(
                "MCPClient: Failed to parse response: \(error), raw: \(msg)\n".data(using: .utf8)!
            )
        }
    }
}

// MARK: - Errors

enum MCPError: LocalizedError {
    case notConnected
    case alreadyConnected
    case disconnected
    case invalidResponse(String)
    case serverError(code: Int, message: String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to MCP bridge"
        case .alreadyConnected: return "Already connected to MCP bridge"
        case .disconnected: return "Disconnected from MCP bridge"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .serverError(let code, let msg): return "Server error [\(code)]: \(msg)"
        case .timeout: return "Request timed out"
        }
    }
}
