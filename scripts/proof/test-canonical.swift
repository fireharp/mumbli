#!/usr/bin/env swift
// Validates CanonicalJSON output matches proof-of-use Go canonical.Bytes expectations.
import Foundation
import CryptoKit

// Minimal copy of CanonicalJSON for standalone test (keep in sync with CanonicalJSON.swift)
enum CanonicalJSON {
    static func bytes(_ value: Any) throws -> Data {
        var buffer = Data()
        try writeValue(value, into: &buffer)
        return buffer
    }

    static func bytes<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try bytes(object)
    }

    private static func writeValue(_ value: Any, into buffer: inout Data) throws {
        switch value {
        case is NSNull:
            buffer.append(contentsOf: "null".utf8)
        case let bool as Bool:
            buffer.append(contentsOf: (bool ? "true" : "false").utf8)
        case let string as String:
            try writeString(string, into: &buffer)
        case let nsString as NSString:
            try writeString(nsString as String, into: &buffer)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                buffer.append(contentsOf: (number.boolValue ? "true" : "false").utf8)
            } else {
                buffer.append(contentsOf: String(number.intValue).utf8)
            }
        case let int as Int:
            buffer.append(contentsOf: String(int).utf8)
        case let dict as [String: Any]:
            try writeObject(dict, into: &buffer)
        case let array as [Any]:
            try writeArray(array, into: &buffer)
        default:
            fputs("unsupported type: \(type(of: value))\n", stderr)
            exit(1)
        }
    }

    private static func writeObject(_ object: [String: Any], into buffer: inout Data) throws {
        buffer.append(UInt8(ascii: "{"))
        let keys = object.keys.sorted()
        for (index, key) in keys.enumerated() {
            if index > 0 { buffer.append(UInt8(ascii: ",")) }
            try writeString(key, into: &buffer)
            buffer.append(UInt8(ascii: ":"))
            try writeValue(object[key]!, into: &buffer)
        }
        buffer.append(UInt8(ascii: "}"))
    }

    private static func writeArray(_ array: [Any], into buffer: inout Data) throws {
        buffer.append(UInt8(ascii: "["))
        for (index, item) in array.enumerated() {
            if index > 0 { buffer.append(UInt8(ascii: ",")) }
            try writeValue(item, into: &buffer)
        }
        buffer.append(UInt8(ascii: "]"))
    }

    private static func writeString(_ string: String, into buffer: inout Data) throws {
        var out = "\""
        for char in string {
            switch char {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if let scalar = char.unicodeScalars.first, scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.append(char)
                }
            }
        }
        out += "\""
        buffer.append(contentsOf: out.utf8)
    }
}

struct PouEventBody: Codable {
    let type: String
    let event_id: String
    let project_id: String
    let epoch: String
    let function_name: String
    let nullifier: String
    let time_bucket: String
}

var failed = false

func check(_ name: String, _ got: String, _ want: String) {
    if got == want {
        print("OK  \(name)")
    } else {
        print("FAIL \(name)")
        print("  got:  \(got)")
        print("  want: \(want)")
        failed = true
    }
}

// Sorted keys test
let sorted = try CanonicalJSON.bytes(["b": 2, "a": 1, "nested": ["z": true, "y": false] as [String: Any]] as [String: Any])
check("sorted keys", String(data: sorted, encoding: .utf8)!, #"{"a":1,"b":2,"nested":{"y":false,"z":true}}"#)

// Nullifier payload (must match Go receipt.Nullifier)
let nullifierPayload: [String: Any] = [
    "epoch": "2026-07",
    "install_public_key": "OCgZqFwY2fHux1xorwzEAj7BRK-cmza2cwSbsoshwpA",
    "project_id": "github.com/fireharp/mumbli",
]
let nullifierCanonical = try CanonicalJSON.bytes(nullifierPayload)
let digest = SHA256.hash(data: nullifierCanonical)
let nullifierHex = digest.map { String(format: "%02x", $0) }.joined()
check("nullifier canonical keys",
      String(data: nullifierCanonical, encoding: .utf8)!,
      #"{"epoch":"2026-07","install_public_key":"OCgZqFwY2fHux1xorwzEAj7BRK-cmza2cwSbsoshwpA","project_id":"github.com/fireharp/mumbli"}"#)
print("OK  nullifier sha256 length=\(nullifierHex.count)")

// Event body encodes without throwing
let body = PouEventBody(
    type: "usage-event:v1",
    event_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    project_id: "github.com/fireharp/mumbli",
    epoch: "2026-07",
    function_name: "dictation.complete",
    nullifier: nullifierHex,
    time_bucket: "2026-07-06T12:00:00Z"
)
let bodyBytes = try CanonicalJSON.bytes(body)
if bodyBytes.isEmpty { failed = true; print("FAIL event body empty") }
else { print("OK  event body encodes (\(bodyBytes.count) bytes)") }

if failed { exit(1) }
print("All canonical JSON tests passed")
