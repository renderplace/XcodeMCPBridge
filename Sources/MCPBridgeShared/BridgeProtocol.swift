//
//  BridgeProtocol.swift
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

// MARK: - App → CLI Commands

public struct BridgeCommand: Codable, Sendable {
    public let id: String
    public let action: BridgeAction

    public init(id: String = UUID().uuidString, action: BridgeAction) {
        self.id = id
        self.action = action
    }
}

public enum BridgeAction: Codable, Sendable {
    case connect
    case listTools
    case callTool(name: String, arguments: [String: String])
    case disconnect

    private enum CodingKeys: String, CodingKey {
        case type, name, arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connect:
            try container.encode("connect", forKey: .type)
        case .listTools:
            try container.encode("listTools", forKey: .type)
        case .callTool(let name, let arguments):
            try container.encode("callTool", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(arguments, forKey: .arguments)
        case .disconnect:
            try container.encode("disconnect", forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "connect":
            self = .connect
        case "listTools":
            self = .listTools
        case "callTool":
            let name = try container.decode(String.self, forKey: .name)
            let arguments = try container.decodeIfPresent([String: String].self, forKey: .arguments) ?? [:]
            self = .callTool(name: name, arguments: arguments)
        case "disconnect":
            self = .disconnect
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }
}

// MARK: - CLI → App Responses

public struct BridgeResponse: Codable, Sendable {
    public let id: String?
    public let status: BridgeStatus
    public let data: BridgeResponseData?
    public let error: String?

    public init(id: String?, status: BridgeStatus, data: BridgeResponseData? = nil, error: String? = nil) {
        self.id = id
        self.status = status
        self.data = data
        self.error = error
    }
}

public enum BridgeStatus: String, Codable, Sendable {
    case ok
    case error
    case info
}

public enum BridgeResponseData: Codable, Sendable {
    case connected(BridgeServerInfo)
    case tools([MCPTool])
    case toolResult(BridgeToolResult)
    case disconnected
    case message(String)

    private enum CodingKeys: String, CodingKey {
        case type, serverInfo, tools, result, message
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connected(let info):
            try container.encode("connected", forKey: .type)
            try container.encode(info, forKey: .serverInfo)
        case .tools(let tools):
            try container.encode("tools", forKey: .type)
            try container.encode(tools, forKey: .tools)
        case .toolResult(let result):
            try container.encode("toolResult", forKey: .type)
            try container.encode(result, forKey: .result)
        case .disconnected:
            try container.encode("disconnected", forKey: .type)
        case .message(let msg):
            try container.encode("message", forKey: .type)
            try container.encode(msg, forKey: .message)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "connected":
            let info = try container.decode(BridgeServerInfo.self, forKey: .serverInfo)
            self = .connected(info)
        case "tools":
            let tools = try container.decode([MCPTool].self, forKey: .tools)
            self = .tools(tools)
        case "toolResult":
            let result = try container.decode(BridgeToolResult.self, forKey: .result)
            self = .toolResult(result)
        case "disconnected":
            self = .disconnected
        case "message":
            let msg = try container.decode(String.self, forKey: .message)
            self = .message(msg)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown response data type: \(type)"
            )
        }
    }
}

public struct BridgeServerInfo: Codable, Sendable, Equatable {
    public let name: String
    public let version: String
    public let protocolVersion: String

    public init(name: String, version: String, protocolVersion: String) {
        self.name = name
        self.version = version
        self.protocolVersion = protocolVersion
    }
}

public struct BridgeToolResult: Codable, Sendable, Equatable {
    public let content: [MCPContentItem]
    public let isError: Bool

    public init(content: [MCPContentItem], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}
