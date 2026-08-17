import Foundation

/// Deterministic JSON encoding matching proof-of-use Go canonical.Bytes:
/// sorted object keys, no whitespace, arrays preserve order.
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
        case let int64 as Int64:
            buffer.append(contentsOf: String(int64).utf8)
        case let double as Double:
            if double == Double(Int64(double)) {
                buffer.append(contentsOf: String(Int64(double)).utf8)
            } else {
                throw CanonicalJSONError.unsupportedFloat
            }
        case let dict as [String: Any]:
            try writeObject(dict, into: &buffer)
        case let array as [Any]:
            try writeArray(array, into: &buffer)
        default:
            throw CanonicalJSONError.unsupportedType(String(describing: type(of: value)))
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
        // Match Go encoding/json string escaping (does not escape '/').
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

enum CanonicalJSONError: Error, CustomStringConvertible {
    case unsupportedFloat
    case unsupportedType(String)

    var description: String {
        switch self {
        case .unsupportedFloat:
            return "non-integer float not supported in canonical JSON"
        case .unsupportedType(let type):
            return "unsupported type in canonical JSON: \(type)"
        }
    }
}
