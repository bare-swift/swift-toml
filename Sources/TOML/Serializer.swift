// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// TOML 1.0 serializer. Emits scalar key/value pairs first at each level,
/// then nested table headers in document order. Insertion order is
/// preserved from the input ``TOMLValue``.
///
/// Strings are emitted as basic strings with escape sequences for the
/// usual non-printable characters; values requiring quoting beyond what
/// basic-string supports are still emitted as basic strings (the parser
/// accepts them on round-trip).
enum Serializer {
    static func serialize(_ value: TOMLValue) -> String {
        guard case .table(let entries) = value else {
            return ""
        }
        var out = ""
        emitTable(entries, prefix: [], into: &out)
        return out
    }

    private static func emitTable(_ entries: [TOMLValue.Entry], prefix: [String], into out: inout String) {
        // First, emit key/value pairs at this level.
        var nestedTables: [(path: [String], entries: [TOMLValue.Entry])] = []
        var nestedArraysOfTables: [(path: [String], items: [[TOMLValue.Entry]])] = []

        for entry in entries {
            switch entry.value {
            case .table(let sub):
                nestedTables.append((prefix + [entry.key], sub))
            case .array(let items) where items.allSatisfy({ if case .table = $0 { return true } else { return false } }):
                let unpacked: [[TOMLValue.Entry]] = items.compactMap {
                    if case .table(let e) = $0 { return e } else { return nil }
                }
                nestedArraysOfTables.append((prefix + [entry.key], unpacked))
            default:
                out.append(escapeKey(entry.key))
                out.append(" = ")
                out.append(emitValue(entry.value))
                out.append("\n")
            }
        }

        for nt in nestedTables {
            out.append("\n[")
            out.append(nt.path.map(escapeKey).joined(separator: "."))
            out.append("]\n")
            emitTable(nt.entries, prefix: nt.path, into: &out)
        }

        for at in nestedArraysOfTables {
            for item in at.items {
                out.append("\n[[")
                out.append(at.path.map(escapeKey).joined(separator: "."))
                out.append("]]\n")
                emitTable(item, prefix: at.path, into: &out)
            }
        }
    }

    private static func emitValue(_ value: TOMLValue) -> String {
        switch value {
        case .string(let s):
            return emitBasicString(s)
        case .integer(let n):
            return String(n)
        case .float(let f):
            if f.isNaN { return "nan" }
            if f.isInfinite { return f > 0 ? "inf" : "-inf" }
            // Ensure round-trip by always including a decimal point.
            let s = String(f)
            return s.contains(".") || s.contains("e") || s.contains("E") ? s : s + ".0"
        case .bool(let b):
            return b ? "true" : "false"
        case .datetime(let s):
            return s
        case .array(let items):
            return "[" + items.map(emitValue).joined(separator: ", ") + "]"
        case .table(let entries):
            // Inline table form.
            let pairs = entries.map { "\(escapeKey($0.key)) = \(emitValue($0.value))" }
            return "{ " + pairs.joined(separator: ", ") + " }"
        }
    }

    private static func emitBasicString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            default:
                if scalar.value < 0x20 {
                    out.append("\\u")
                    out.append(String(scalar.value, radix: 16, uppercase: true).leftPadding(toLength: 4, withPad: "0"))
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append("\"")
        return out
    }

    private static func escapeKey(_ key: String) -> String {
        // Bare key allowed if it matches A-Za-z0-9_- and is non-empty.
        if !key.isEmpty,
           key.unicodeScalars.allSatisfy({
               let v = $0.value
               return (v >= 0x30 && v <= 0x39) ||
                      (v >= 0x41 && v <= 0x5A) ||
                      (v >= 0x61 && v <= 0x7A) ||
                      $0 == "_" || $0 == "-"
           }) {
            return key
        }
        return emitBasicString(key)
    }
}

extension String {
    fileprivate func leftPadding(toLength: Int, withPad pad: Character) -> String {
        let len = self.count
        if len >= toLength { return self }
        return String(repeating: pad, count: toLength - len) + self
    }
}
