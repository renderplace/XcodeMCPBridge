//
//  main.swift
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

/// MCPBridgeCLI - A companion CLI that acts as an MCP client for Apple's xcrun mcpbridge.
///
/// Communication:
/// - Reads BridgeCommand JSON from stdin (one per line)
/// - Writes BridgeResponse JSON to stdout (one per line)
/// - Diagnostic messages go to stderr

let client = MCPClient()
let encoder = JSONEncoder()
let decoder = JSONDecoder()

func send(_ response: BridgeResponse) {
    guard let data = try? encoder.encode(response),
          let line = String(data: data, encoding: .utf8)
    else { return }
    print(line)
    fflush(stdout)
}

func logError(_ message: String) {
    FileHandle.standardError.write("[mcpbridge-cli] \(message)\n".data(using: .utf8)!)
}

func handleCommand(_ command: BridgeCommand) async {
    switch command.action {
    case .connect:
        do {
            let xcodePID = ProcessInfo.processInfo.environment["MCP_XCODE_PID"]
            let sessionID = ProcessInfo.processInfo.environment["MCP_XCODE_SESSION_ID"]
            let result = try await client.connect(xcodePID: xcodePID, sessionID: sessionID)

            let serverInfo = BridgeServerInfo(
                name: result.serverInfo?.name ?? "Xcode",
                version: result.serverInfo?.version ?? "unknown",
                protocolVersion: result.protocolVersion ?? "unknown"
            )
            send(BridgeResponse(
                id: command.id,
                status: .ok,
                data: .connected(serverInfo)
            ))
        } catch {
            send(BridgeResponse(
                id: command.id,
                status: .error,
                error: "Failed to connect: \(error.localizedDescription)"
            ))
        }

    case .listTools:
        do {
            let tools = try await client.listTools()
            send(BridgeResponse(
                id: command.id,
                status: .ok,
                data: .tools(tools)
            ))
        } catch {
            send(BridgeResponse(
                id: command.id,
                status: .error,
                error: "Failed to list tools: \(error.localizedDescription)"
            ))
        }

    case .callTool(let name, let arguments):
        do {
            let result = try await client.callTool(name: name, arguments: arguments)
            let bridgeResult = BridgeToolResult(
                content: result.content ?? [],
                isError: result.isError ?? false
            )
            send(BridgeResponse(
                id: command.id,
                status: .ok,
                data: .toolResult(bridgeResult)
            ))
        } catch {
            send(BridgeResponse(
                id: command.id,
                status: .error,
                error: "Tool call failed: \(error.localizedDescription)"
            ))
        }

    case .disconnect:
        await client.disconnect()
        send(BridgeResponse(
            id: command.id,
            status: .ok,
            data: .disconnected
        ))
    }
}

// MARK: - Main Loop

logError("Starting MCPBridgeCLI...")

// Use a semaphore to keep the process alive while async tasks run
let semaphore = DispatchSemaphore(value: 0)

Task {
    // Read commands from stdin line by line
    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty else { continue }

        guard let data = line.data(using: .utf8) else {
            logError("Failed to read line as UTF-8")
            continue
        }

        do {
            let command = try decoder.decode(BridgeCommand.self, from: data)
            await handleCommand(command)
        } catch {
            logError("Failed to parse command: \(error), raw: \(line)")
            send(BridgeResponse(
                id: nil,
                status: .error,
                error: "Invalid command: \(error.localizedDescription)"
            ))
        }
    }

    // stdin closed - clean up
    logError("stdin closed, shutting down")
    await client.disconnect()
    semaphore.signal()
}

semaphore.wait()
