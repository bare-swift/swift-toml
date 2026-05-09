// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// TOML 1.0 parser. Recursive-descent over Unicode scalars, building an
/// in-memory tree of ``TableNode`` nodes that converts to ``TOMLValue`` at
/// the end. Datetime values are preserved as raw text per RFC-0010.
///
/// The top-level grammar is line-oriented:
///
/// ```
/// expression   = ws ( comment / keyval / table ) ws
/// table        = stdTable / arrayTable
/// stdTable     = "[" ws key ws "]"
/// arrayTable   = "[[" ws key ws "]]"
/// keyval       = key ws "=" ws val
/// ```
///
/// Inside `val`, the spec is more involved: strings (basic / multi-line
/// basic / literal / multi-line literal), integers (decimal / hex /
/// octal / binary with underscore separators), floats, booleans,
/// datetimes (offset / local / date-only / time-only), arrays, and
/// inline tables. The parser is intentionally written in a flat,
/// procedural style so each TOML production maps to a named function.
enum Parser {
    static func parse(_ input: String) throws(TOMLError) -> TOMLValue {
        var ctx = ParserContext(input: input)
        let root = TableNode()
        var current = root
        var explicitTables: Set<ObjectIdentifier> = []

        while true {
            ctx.skipWhitespaceAndNewlines()
            if ctx.atEnd { break }

            let c = ctx.peek()!
            if c == "[" {
                if ctx.peek(offset: 1) == "[" {
                    ctx.advance(2)
                    let path = try ctx.parseKeyPath()
                    try ctx.expect("]")
                    try ctx.expect("]")
                    current = try navigateToArrayElement(root: root, path: path, line: ctx.line)
                } else {
                    ctx.advance(1)
                    let path = try ctx.parseKeyPath()
                    try ctx.expect("]")
                    let target = try navigateToTable(root: root, path: path, line: ctx.line, redeclareExplicit: explicitTables)
                    explicitTables.insert(ObjectIdentifier(target))
                    current = target
                }
                try ctx.consumeRestOfLine()
            } else {
                let path = try ctx.parseKeyPath()
                ctx.skipInlineWhitespace()
                try ctx.expect("=")
                ctx.skipInlineWhitespace()
                let value = try ctx.parseValue()
                try insertKeyValue(into: current, path: path, value: value, line: ctx.line)
                try ctx.consumeRestOfLine()
            }
        }

        return root.toTOMLValue()
    }

    // MARK: - Tree mutation

    static func navigateToTable(
        root: TableNode,
        path: [String],
        line: Int,
        redeclareExplicit: Set<ObjectIdentifier>
    ) throws(TOMLError) -> TableNode {
        var node = root
        for (i, segment) in path.enumerated() {
            if let existing = node.entries[segment] {
                switch existing {
                case .scalar:
                    throw .invalidTable(path.joined(separator: "."), line: line)
                case .table(let t):
                    if i == path.count - 1 && redeclareExplicit.contains(ObjectIdentifier(t)) {
                        throw .duplicateKey(path.joined(separator: "."), line: line)
                    }
                    node = t
                case .arrayOfTables(let arr):
                    // Walking into the last element of an array-of-tables is allowed.
                    if let last = arr.last {
                        node = last
                    } else {
                        throw .invalidTable(path.joined(separator: "."), line: line)
                    }
                }
            } else {
                let new = TableNode()
                node.entries[segment] = .table(new)
                node.insertionOrder.append(segment)
                node = new
            }
        }
        return node
    }

    static func navigateToArrayElement(
        root: TableNode,
        path: [String],
        line: Int
    ) throws(TOMLError) -> TableNode {
        // Walk to the parent of the last segment.
        var node = root
        for segment in path.dropLast() {
            if let existing = node.entries[segment] {
                switch existing {
                case .table(let t):
                    node = t
                case .arrayOfTables(let arr):
                    if let last = arr.last { node = last }
                    else { throw .invalidTable(path.joined(separator: "."), line: line) }
                case .scalar:
                    throw .invalidTable(path.joined(separator: "."), line: line)
                }
            } else {
                let new = TableNode()
                node.entries[segment] = .table(new)
                node.insertionOrder.append(segment)
                node = new
            }
        }
        let lastSeg = path.last!
        if let existing = node.entries[lastSeg] {
            switch existing {
            case .arrayOfTables(var arr):
                let new = TableNode()
                arr.append(new)
                node.entries[lastSeg] = .arrayOfTables(arr)
                return new
            default:
                throw .invalidTable(path.joined(separator: "."), line: line)
            }
        } else {
            let new = TableNode()
            node.entries[lastSeg] = .arrayOfTables([new])
            node.insertionOrder.append(lastSeg)
            return new
        }
    }

    static func insertKeyValue(
        into current: TableNode,
        path: [String],
        value: TOMLValue,
        line: Int
    ) throws(TOMLError) {
        var node = current
        for segment in path.dropLast() {
            if let existing = node.entries[segment] {
                switch existing {
                case .table(let t):
                    node = t
                case .scalar, .arrayOfTables:
                    throw .duplicateKey(path.joined(separator: "."), line: line)
                }
            } else {
                let new = TableNode()
                node.entries[segment] = .table(new)
                node.insertionOrder.append(segment)
                node = new
            }
        }
        let lastSeg = path.last!
        if node.entries[lastSeg] != nil {
            throw .duplicateKey(path.joined(separator: "."), line: line)
        }
        node.entries[lastSeg] = .scalar(value)
        node.insertionOrder.append(lastSeg)
    }
}

/// Internal in-memory representation built during parsing. Converts to
/// ``TOMLValue`` once the document is complete. Class-typed (rather than
/// value-typed) so deep mutation through nested tables is straightforward.
final class TableNode {
    var entries: [String: NodeValue] = [:]
    var insertionOrder: [String] = []

    func toTOMLValue() -> TOMLValue {
        var out: [TOMLValue.Entry] = []
        out.reserveCapacity(insertionOrder.count)
        for key in insertionOrder {
            guard let v = entries[key] else { continue }
            switch v {
            case .scalar(let value):
                out.append(.init(key: key, value: value))
            case .table(let t):
                out.append(.init(key: key, value: t.toTOMLValue()))
            case .arrayOfTables(let arr):
                let mapped: [TOMLValue] = arr.map { $0.toTOMLValue() }
                out.append(.init(key: key, value: .array(mapped)))
            }
        }
        return .table(out)
    }
}

enum NodeValue {
    case scalar(TOMLValue)
    case table(TableNode)
    case arrayOfTables([TableNode])
}

// MARK: - ParserContext

struct ParserContext {
    let scalars: [Unicode.Scalar]
    var cursor: Int = 0
    var line: Int = 1
    var column: Int = 1

    init(input: String) {
        self.scalars = Array(input.unicodeScalars)
    }

    var atEnd: Bool { cursor >= scalars.count }

    func peek(offset: Int = 0) -> Unicode.Scalar? {
        let i = cursor + offset
        return i < scalars.count ? scalars[i] : nil
    }

    mutating func advance(_ n: Int = 1) {
        for _ in 0..<n {
            guard cursor < scalars.count else { return }
            if scalars[cursor] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            cursor += 1
        }
    }

    mutating func expect(_ expected: Unicode.Scalar) throws(TOMLError) {
        guard let c = peek() else { throw .unexpectedEOF }
        if c != expected {
            throw .unexpectedCharacter(Character(c), line: line, column: column)
        }
        advance(1)
    }

    mutating func skipInlineWhitespace() {
        while let c = peek(), c == " " || c == "\t" {
            advance(1)
        }
    }

    mutating func skipWhitespaceAndNewlines() {
        while let c = peek() {
            if c == " " || c == "\t" || c == "\n" || c == "\r" {
                advance(1)
            } else if c == "#" {
                // comment — consume to end of line
                while let cc = peek(), cc != "\n" { advance(1) }
            } else {
                break
            }
        }
    }

    /// After a logical statement, consume optional inline whitespace, an
    /// optional comment, and either a newline or EOF.
    mutating func consumeRestOfLine() throws(TOMLError) {
        skipInlineWhitespace()
        if let c = peek(), c == "#" {
            while let cc = peek(), cc != "\n" { advance(1) }
        }
        if let c = peek() {
            if c == "\n" || c == "\r" {
                advance(1)
                if c == "\r", peek() == "\n" { advance(1) }
            } else {
                throw .unexpectedCharacter(Character(c), line: line, column: column)
            }
        }
    }

    // MARK: - Keys

    mutating func parseKeyPath() throws(TOMLError) -> [String] {
        var path: [String] = []
        path.append(try parseKeySegment())
        while true {
            skipInlineWhitespace()
            if peek() == "." {
                advance(1)
                skipInlineWhitespace()
                path.append(try parseKeySegment())
            } else {
                break
            }
        }
        return path
    }

    mutating func parseKeySegment() throws(TOMLError) -> String {
        guard let c = peek() else { throw .unexpectedEOF }
        if c == "\"" {
            advance(1)
            return try parseBasicStringBody()
        }
        if c == "'" {
            advance(1)
            return try parseLiteralStringBody()
        }
        // Bare key: A-Za-z0-9_-
        var s = ""
        while let cc = peek(), isBareKeyChar(cc) {
            s.unicodeScalars.append(cc)
            advance(1)
        }
        if s.isEmpty {
            throw .invalidKey(line: line)
        }
        return s
    }

    func isBareKeyChar(_ c: Unicode.Scalar) -> Bool {
        let v = c.value
        if v >= 0x30 && v <= 0x39 { return true }
        if v >= 0x41 && v <= 0x5A { return true }
        if v >= 0x61 && v <= 0x7A { return true }
        return c == "_" || c == "-"
    }

    // MARK: - Values

    mutating func parseValue() throws(TOMLError) -> TOMLValue {
        guard let c = peek() else { throw .unexpectedEOF }
        switch c {
        case "\"":
            if peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
                advance(3)
                return .string(try parseMultilineBasicStringBody())
            } else {
                advance(1)
                return .string(try parseBasicStringBody())
            }
        case "'":
            if peek(offset: 1) == "'" && peek(offset: 2) == "'" {
                advance(3)
                return .string(try parseMultilineLiteralStringBody())
            } else {
                advance(1)
                return .string(try parseLiteralStringBody())
            }
        case "[":
            advance(1)
            return try parseInlineArray()
        case "{":
            advance(1)
            return try parseInlineTable()
        case "t", "f":
            return try parseBool()
        default:
            return try parseNumberOrDatetime()
        }
    }

    // MARK: - Strings

    mutating func parseBasicStringBody() throws(TOMLError) -> String {
        var s = ""
        while let c = peek() {
            if c == "\"" {
                advance(1)
                return s
            }
            if c == "\n" {
                throw .unterminatedString(line: line)
            }
            if c == "\\" {
                advance(1)
                s.unicodeScalars.append(try parseEscape())
            } else {
                s.unicodeScalars.append(c)
                advance(1)
            }
        }
        throw .unterminatedString(line: line)
    }

    mutating func parseMultilineBasicStringBody() throws(TOMLError) -> String {
        // Per spec: a newline immediately after opening """ is trimmed.
        if peek() == "\r", peek(offset: 1) == "\n" { advance(2) }
        else if peek() == "\n" { advance(1) }

        var s = ""
        while let c = peek() {
            if c == "\"" && peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
                // Allow up to two more " before terminator (i.e. "" or "")
                advance(3)
                if peek() == "\"" {
                    s.append("\"")
                    advance(1)
                    if peek() == "\"" {
                        s.append("\"")
                        advance(1)
                    }
                }
                return s
            }
            if c == "\\" {
                // Line-ending backslash (line-trim) per TOML 1.0 § Strings.
                let nextNonInlineWS = peekSkippingInlineWS(offset: 1)
                if nextNonInlineWS == "\n" || (nextNonInlineWS == "\r" && peek(offset: 2) == "\n") {
                    advance(1) // backslash
                    while let cc = peek(), cc == " " || cc == "\t" { advance(1) }
                    while let cc = peek(), cc == "\n" || cc == "\r" || cc == " " || cc == "\t" {
                        advance(1)
                    }
                    continue
                }
                advance(1)
                s.unicodeScalars.append(try parseEscape())
            } else {
                s.unicodeScalars.append(c)
                advance(1)
            }
        }
        throw .unterminatedString(line: line)
    }

    private func peekSkippingInlineWS(offset: Int) -> Unicode.Scalar? {
        var i = cursor + offset
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" { i += 1 }
        return i < scalars.count ? scalars[i] : nil
    }

    mutating func parseLiteralStringBody() throws(TOMLError) -> String {
        var s = ""
        while let c = peek() {
            if c == "'" {
                advance(1)
                return s
            }
            if c == "\n" {
                throw .unterminatedString(line: line)
            }
            s.unicodeScalars.append(c)
            advance(1)
        }
        throw .unterminatedString(line: line)
    }

    mutating func parseMultilineLiteralStringBody() throws(TOMLError) -> String {
        if peek() == "\r", peek(offset: 1) == "\n" { advance(2) }
        else if peek() == "\n" { advance(1) }

        var s = ""
        while let c = peek() {
            if c == "'" && peek(offset: 1) == "'" && peek(offset: 2) == "'" {
                advance(3)
                if peek() == "'" {
                    s.append("'")
                    advance(1)
                    if peek() == "'" {
                        s.append("'")
                        advance(1)
                    }
                }
                return s
            }
            s.unicodeScalars.append(c)
            advance(1)
        }
        throw .unterminatedString(line: line)
    }

    mutating func parseEscape() throws(TOMLError) -> Unicode.Scalar {
        guard let c = peek() else { throw .unexpectedEOF }
        advance(1)
        switch c {
        case "b": return Unicode.Scalar(0x08)!
        case "t": return "\t"
        case "n": return "\n"
        case "f": return Unicode.Scalar(0x0C)!
        case "r": return "\r"
        case "\"": return "\""
        case "\\": return "\\"
        case "u":
            let hex = try readHexDigits(count: 4)
            guard let scalar = Unicode.Scalar(hex) else {
                throw .invalidEscape("\\u\(String(hex, radix: 16))", line: line)
            }
            return scalar
        case "U":
            let hex = try readHexDigits(count: 8)
            guard let scalar = Unicode.Scalar(hex) else {
                throw .invalidEscape("\\U\(String(hex, radix: 16))", line: line)
            }
            return scalar
        default:
            throw .invalidEscape("\\\(Character(c))", line: line)
        }
    }

    mutating func readHexDigits(count: Int) throws(TOMLError) -> UInt32 {
        var v: UInt32 = 0
        for _ in 0..<count {
            guard let c = peek() else { throw .unexpectedEOF }
            guard let d = hexDigitValue(c) else {
                throw .invalidEscape(String(c), line: line)
            }
            v = (v << 4) | d
            advance(1)
        }
        return v
    }

    func hexDigitValue(_ c: Unicode.Scalar) -> UInt32? {
        let v = c.value
        if v >= 0x30 && v <= 0x39 { return v - 0x30 }
        if v >= 0x41 && v <= 0x46 { return v - 0x41 + 10 }
        if v >= 0x61 && v <= 0x66 { return v - 0x61 + 10 }
        return nil
    }

    // MARK: - Numbers / datetimes / bool

    mutating func parseBool() throws(TOMLError) -> TOMLValue {
        if matches("true") {
            advance(4)
            return .bool(true)
        }
        if matches("false") {
            advance(5)
            return .bool(false)
        }
        throw .invalidValue(line: line)
    }

    func matches(_ keyword: String) -> Bool {
        let kw = Array(keyword.unicodeScalars)
        guard cursor + kw.count <= scalars.count else { return false }
        for i in 0..<kw.count {
            if scalars[cursor + i] != kw[i] { return false }
        }
        // No trailing key-char to avoid `truely` matching `true`
        if cursor + kw.count < scalars.count {
            let next = scalars[cursor + kw.count]
            if isBareKeyChar(next) { return false }
        }
        return true
    }

    /// Read a number-or-datetime value. Datetimes are recognised by the
    /// shape `YYYY-MM-DD` (date / datetime) or `HH:MM:SS` (local time);
    /// everything else is integer or float.
    mutating func parseNumberOrDatetime() throws(TOMLError) -> TOMLValue {
        // Lookahead for datetime patterns — they always begin with digits.
        if isDatetimeLookahead() {
            return .datetime(consumeDatetimeString())
        }

        // Number — accumulate the literal then parse it.
        let start = cursor
        if peek() == "+" || peek() == "-" { advance(1) }
        // Special tokens: inf / nan
        if matches("inf") {
            advance(3)
            let s = literal(from: start)
            if s == "+inf" || s == "inf" { return .float(.infinity) }
            if s == "-inf" { return .float(-.infinity) }
            throw .invalidNumber(s, line: line)
        }
        if matches("nan") {
            advance(3)
            return .float(.nan)
        }
        // Hex / octal / binary integer
        if peek() == "0" {
            let base = peek(offset: 1)
            if base == "x" || base == "o" || base == "b" {
                advance(2)
                let radix: Int = (base == "x" ? 16 : (base == "o" ? 8 : 2))
                var digits = ""
                while let c = peek(), isRadixDigit(c, radix: radix) || c == "_" {
                    if c != "_" { digits.unicodeScalars.append(c) }
                    advance(1)
                }
                guard let n = Int64(digits, radix: radix) else {
                    throw .invalidNumber(digits, line: line)
                }
                return .integer(n)
            }
        }

        var sawDot = false
        var sawExp = false
        while let c = peek() {
            if c >= "0" && c <= "9" { advance(1); continue }
            if c == "_" { advance(1); continue }
            if c == "." && !sawDot && !sawExp { sawDot = true; advance(1); continue }
            if (c == "e" || c == "E") && !sawExp {
                sawExp = true
                advance(1)
                if peek() == "+" || peek() == "-" { advance(1) }
                continue
            }
            break
        }
        let raw = literal(from: start)
        let cleaned = raw.replacingOccurrences(Unicode.Scalar("_"), with: nil)
        if sawDot || sawExp {
            guard let f = Double(cleaned) else { throw .invalidNumber(raw, line: line) }
            return .float(f)
        }
        guard let n = Int64(cleaned) else { throw .invalidNumber(raw, line: line) }
        return .integer(n)
    }

    func isRadixDigit(_ c: Unicode.Scalar, radix: Int) -> Bool {
        let v = c.value
        if radix == 16 {
            return (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x46) || (v >= 0x61 && v <= 0x66)
        }
        if radix == 8 { return v >= 0x30 && v <= 0x37 }
        if radix == 2 { return v == 0x30 || v == 0x31 }
        return v >= 0x30 && v <= 0x39
    }

    func literal(from start: Int) -> String {
        var s = ""
        for i in start..<cursor { s.unicodeScalars.append(scalars[i]) }
        return s
    }

    func isDatetimeLookahead() -> Bool {
        // Date / datetime: 4 digits, dash, 2 digits, dash, 2 digits.
        if cursor + 10 <= scalars.count,
           isAsciiDigit(scalars[cursor]),
           isAsciiDigit(scalars[cursor + 1]),
           isAsciiDigit(scalars[cursor + 2]),
           isAsciiDigit(scalars[cursor + 3]),
           scalars[cursor + 4] == "-",
           isAsciiDigit(scalars[cursor + 5]),
           isAsciiDigit(scalars[cursor + 6]),
           scalars[cursor + 7] == "-",
           isAsciiDigit(scalars[cursor + 8]),
           isAsciiDigit(scalars[cursor + 9]) {
            return true
        }
        // Local time: 2 digits, colon, 2 digits, colon, 2 digits.
        if cursor + 8 <= scalars.count,
           isAsciiDigit(scalars[cursor]),
           isAsciiDigit(scalars[cursor + 1]),
           scalars[cursor + 2] == ":",
           isAsciiDigit(scalars[cursor + 3]),
           isAsciiDigit(scalars[cursor + 4]),
           scalars[cursor + 5] == ":",
           isAsciiDigit(scalars[cursor + 6]),
           isAsciiDigit(scalars[cursor + 7]) {
            return true
        }
        return false
    }

    mutating func consumeDatetimeString() -> String {
        var s = ""
        // Datetime characters: 0-9, -, :, T, t, Z, z, +, ., space (between date and time per RFC 3339).
        // Stop at whitespace (other than the legal space between date & time), comma, ], }, #, newline.
        var i = 0
        while let c = peek() {
            // Inside a datetime, allow exactly one space between date and time;
            // any further whitespace ends the value.
            if c == " " {
                // Accept the date-time separator space if the previous char was a digit
                // and the next char looks like a time component.
                if i > 0, peek(offset: 1) != nil,
                   isAsciiDigit(scalars[cursor - 1]),
                   isAsciiDigit(peek(offset: 1)!) {
                    s.append(" ")
                    advance(1)
                    i += 1
                    continue
                }
                break
            }
            if c == "\n" || c == "\r" || c == "," || c == "]" || c == "}" || c == "#" {
                break
            }
            s.unicodeScalars.append(c)
            advance(1)
            i += 1
        }
        return s
    }

    func isAsciiDigit(_ c: Unicode.Scalar) -> Bool {
        c.value >= 0x30 && c.value <= 0x39
    }

    // MARK: - Inline arrays / tables

    mutating func parseInlineArray() throws(TOMLError) -> TOMLValue {
        var items: [TOMLValue] = []
        skipWhitespaceAndNewlines()
        if peek() == "]" {
            advance(1)
            return .array(items)
        }
        while true {
            skipWhitespaceAndNewlines()
            items.append(try parseValue())
            skipWhitespaceAndNewlines()
            if peek() == "," {
                advance(1)
                skipWhitespaceAndNewlines()
                if peek() == "]" {
                    advance(1)
                    return .array(items)
                }
            } else if peek() == "]" {
                advance(1)
                return .array(items)
            } else {
                throw .unexpectedCharacter(peek().map(Character.init) ?? "?", line: line, column: column)
            }
        }
    }

    mutating func parseInlineTable() throws(TOMLError) -> TOMLValue {
        var entries: [TOMLValue.Entry] = []
        skipInlineWhitespace()
        if peek() == "}" {
            advance(1)
            return .table(entries)
        }
        while true {
            skipInlineWhitespace()
            let key = try parseKeyPath()
            skipInlineWhitespace()
            try expect("=")
            skipInlineWhitespace()
            let value = try parseValue()
            entries = mergeIntoInlineTable(entries: entries, path: key, value: value, line: line)
            skipInlineWhitespace()
            if peek() == "," {
                advance(1)
                continue
            }
            if peek() == "}" {
                advance(1)
                return .table(entries)
            }
            throw .unexpectedCharacter(peek().map(Character.init) ?? "?", line: line, column: column)
        }
    }

    func mergeIntoInlineTable(entries: [TOMLValue.Entry], path: [String], value: TOMLValue, line: Int) -> [TOMLValue.Entry] {
        if path.count == 1 {
            return entries + [.init(key: path[0], value: value)]
        }
        // Dotted key inside inline table → nested table.
        let head = path[0]
        let rest = Array(path.dropFirst())
        var copy = entries
        if let idx = copy.firstIndex(where: { $0.key == head }) {
            if case .table(let existing) = copy[idx].value {
                let merged = mergeIntoInlineTable(entries: existing, path: rest, value: value, line: line)
                copy[idx] = .init(key: head, value: .table(merged))
            }
        } else {
            let merged = mergeIntoInlineTable(entries: [], path: rest, value: value, line: line)
            copy.append(.init(key: head, value: .table(merged)))
        }
        return copy
    }
}

// MARK: - Small String helper

extension String {
    fileprivate func replacingOccurrences(_ target: Unicode.Scalar, with replacement: Unicode.Scalar?) -> String {
        var s = ""
        for c in self.unicodeScalars {
            if c == target {
                if let r = replacement { s.unicodeScalars.append(r) }
            } else {
                s.unicodeScalars.append(c)
            }
        }
        return s
    }
}
