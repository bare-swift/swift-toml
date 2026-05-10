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
        // Two passes:
        //   1. Walk entries in order. Emit scalars and *leaf* nested tables
        //      (those with no sub-tables or arrays-of-tables) inline at
        //      their original position. This preserves insertion order
        //      across the parse → serialize → parse round-trip.
        //   2. After the inline pass, emit non-leaf nested tables and
        //      arrays-of-tables as section headers — these MUST come at
        //      the end of this level because a section header redirects
        //      all subsequent key/value lines to that section.
        var deferred: [(path: [String], kind: DeferredKind)] = []

        for entry in entries {
            switch entry.value {
            case .table(let sub) where containsNested(sub):
                deferred.append((prefix + [entry.key], .table(sub)))
            case .array(let items) where items.allSatisfy({ if case .table = $0 { return true } else { return false } }):
                let unpacked: [[TOMLValue.Entry]] = items.compactMap {
                    if case .table(let e) = $0 { return e } else { return nil }
                }
                deferred.append((prefix + [entry.key], .arrayOfTables(unpacked)))
            default:
                out.append(escapeKey(entry.key))
                out.append(" = ")
                out.append(emitValue(entry.value))
                out.append("\n")
            }
        }

        for d in deferred {
            switch d.kind {
            case .table(let inner):
                out.append("\n[")
                out.append(d.path.map(escapeKey).joined(separator: "."))
                out.append("]\n")
                emitTable(inner, prefix: d.path, into: &out)
            case .arrayOfTables(let items):
                for item in items {
                    out.append("\n[[")
                    out.append(d.path.map(escapeKey).joined(separator: "."))
                    out.append("]]\n")
                    emitTable(item, prefix: d.path, into: &out)
                }
            }
        }
    }

    private enum DeferredKind {
        case table([TOMLValue.Entry])
        case arrayOfTables([[TOMLValue.Entry]])
    }

    /// A "non-leaf" table contains at least one sub-table or array-of-tables,
    /// directly or transitively. Such tables are emitted as section headers
    /// at the end of the level. "Leaf" tables (only scalars / inline arrays
    /// of scalars / nested leaf tables) are emitted inline at their original
    /// position to preserve ordering.
    private static func containsNested(_ entries: [TOMLValue.Entry]) -> Bool {
        for e in entries {
            switch e.value {
            case .table(let inner):
                if containsNested(inner) { return true }
            case .array(let items):
                if items.contains(where: { if case .table = $0 { return true } else { return false } }) {
                    return true
                }
            default:
                continue
            }
        }
        return false
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
