//
//  MCPModels.swift
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

// MARK: - JSON-RPC 2.0 Base Types

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: AnyCodable?

    public init(id: Int? = nil, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let result: AnyCodable?
    public let error: JSONRPCError?
}

public struct JSONRPCError: Codable, Sendable, Equatable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public static func == (lhs: JSONRPCError, rhs: JSONRPCError) -> Bool {
        lhs.code == rhs.code && lhs.message == rhs.message
    }
}

// MARK: - MCP Initialize

public struct MCPClientInfo: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public struct MCPInitializeParams: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: [String: AnyCodable]
    public let clientInfo: MCPClientInfo

    public init(
        protocolVersion: String = "2024-11-05",
        capabilities: [String: AnyCodable] = [:],
        clientInfo: MCPClientInfo = MCPClientInfo(name: "MCPBridgeCLI", version: "1.0.0")
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

public struct MCPServerInfo: Codable, Sendable, Equatable {
    public let name: String?
    public let version: String?
}

public struct MCPInitializeResult: Codable, Sendable {
    public let protocolVersion: String?
    public let capabilities: AnyCodable?
    public let serverInfo: MCPServerInfo?
}

// MARK: - MCP Tools

public struct MCPTool: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: MCPToolInputSchema?

    public init(name: String, description: String? = nil, inputSchema: MCPToolInputSchema? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolInputSchema: Codable, Sendable, Equatable {
    public let type: String?
    public let properties: [String: MCPSchemaProperty]?
    public let required: [String]?
    public let additionalProperties: AnyCodable?
}

public struct MCPSchemaProperty: Codable, Sendable, Equatable {
    public let type: String?
    public let description: String?
    public let `enum`: [String]?
    public let items: AnyCodable?
    public let `default`: AnyCodable?
}

public struct MCPToolsListResult: Codable, Sendable {
    public let tools: [MCPTool]
}

public struct MCPToolCallParams: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodable]?

    public init(name: String, arguments: [String: AnyCodable]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

public struct MCPContentItem: Codable, Sendable, Equatable {
    public let type: String
    public let text: String?
    public let data: String?
    public let mimeType: String?

    public init(type: String, text: String? = nil, data: String? = nil, mimeType: String? = nil) {
        self.type = type
        self.text = text
        self.data = data
        self.mimeType = mimeType
    }
}

public struct MCPToolCallResult: Codable, Sendable {
    public let content: [MCPContentItem]?
    public let isError: Bool?
    public let structuredContent: AnyCodable?
}

// MARK: - AnyCodable (type-erased Codable wrapper)

public struct AnyCodable: Codable, @unchecked Sendable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    // Convenience accessors
    public var stringValue: String? { value as? String }
    public var intValue: Int? { value as? Int }
    public var doubleValue: Double? { value as? Double }
    public var boolValue: Bool? { value as? Bool }
    public var arrayValue: [Any]? { value as? [Any] }
    public var dictValue: [String: Any]? { value as? [String: Any] }
}
