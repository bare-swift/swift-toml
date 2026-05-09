// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
@testable import TOML

/// Helper: extract `entries` from a top-level table value.
private func entries(_ v: TOMLValue) -> [TOMLValue.Entry] {
    if case .table(let e) = v { return e }
    Issue.record("expected top-level table; got \(v)")
    return []
}

private func value(_ entries: [TOMLValue.Entry], for key: String) -> TOMLValue? {
    entries.first { $0.key == key }?.value
}

@Suite("Parser — primitives")
struct ParserPrimitivesTests {
    @Test("empty document → empty table")
    func empty() throws {
        let v = try TOML.parse("")
        if case .table(let e) = v { #expect(e.isEmpty) } else { Issue.record() }
    }

    @Test("simple key=value (string)")
    func keyValueString() throws {
        let v = try TOML.parse(#"name = "alice""#)
        let e = entries(v)
        #expect(e.count == 1)
        #expect(value(e, for: "name") == .string("alice"))
    }

    @Test("integer values")
    func integers() throws {
        let v = try TOML.parse("""
        a = 42
        b = -7
        c = +99
        d = 1_000_000
        """)
        let e = entries(v)
        #expect(value(e, for: "a") == .integer(42))
        #expect(value(e, for: "b") == .integer(-7))
        #expect(value(e, for: "c") == .integer(99))
        #expect(value(e, for: "d") == .integer(1_000_000))
    }

    @Test("hex / octal / binary integers")
    func radixIntegers() throws {
        let v = try TOML.parse("""
        h = 0xDEADBEEF
        o = 0o755
        b = 0b1010
        """)
        let e = entries(v)
        #expect(value(e, for: "h") == .integer(0xDEADBEEF))
        #expect(value(e, for: "o") == .integer(0o755))
        #expect(value(e, for: "b") == .integer(0b1010))
    }

    @Test("float values")
    func floats() throws {
        let v = try TOML.parse("""
        a = 1.0
        b = -0.5
        c = 1e6
        d = 1.5e-3
        e = 3.14
        """)
        let entries = entries(v)
        #expect(value(entries, for: "a") == .float(1.0))
        #expect(value(entries, for: "b") == .float(-0.5))
        #expect(value(entries, for: "c") == .float(1e6))
        #expect(value(entries, for: "d") == .float(1.5e-3))
        #expect(value(entries, for: "e") == .float(3.14))
    }

    @Test("inf / nan")
    func infNan() throws {
        let v = try TOML.parse("""
        a = inf
        b = -inf
        c = +inf
        """)
        let e = entries(v)
        if case .float(let a) = value(e, for: "a")! { #expect(a == .infinity) }
        if case .float(let b) = value(e, for: "b")! { #expect(b == -.infinity) }
        if case .float(let c) = value(e, for: "c")! { #expect(c == .infinity) }
    }

    @Test("booleans")
    func booleans() throws {
        let v = try TOML.parse("""
        a = true
        b = false
        """)
        let e = entries(v)
        #expect(value(e, for: "a") == .bool(true))
        #expect(value(e, for: "b") == .bool(false))
    }

    @Test("comments are ignored")
    func comments() throws {
        let v = try TOML.parse("""
        # a comment
        a = 1 # trailing comment
        # another comment
        b = 2
        """)
        let e = entries(v)
        #expect(value(e, for: "a") == .integer(1))
        #expect(value(e, for: "b") == .integer(2))
    }
}

@Suite("Parser — strings")
struct ParserStringsTests {
    @Test("basic string")
    func basic() throws {
        let v = try TOML.parse(#"name = "hello world""#)
        #expect(value(entries(v), for: "name") == .string("hello world"))
    }

    @Test("basic string escapes")
    func escapes() throws {
        let v = try TOML.parse(#"q = "\"\\\n\t""#)
        #expect(value(entries(v), for: "q") == .string("\"\\\n\t"))
    }

    @Test("unicode escapes (\\u and \\U)")
    func unicodeEscapes() throws {
        let v = try TOML.parse(#"q = "é \U0001F389""#)
        #expect(value(entries(v), for: "q") == .string("é 🎉"))
    }

    @Test("literal string (single quotes)")
    func literalString() throws {
        let v = try TOML.parse(#"q = 'C:\Users\x'"#)
        #expect(value(entries(v), for: "q") == .string(#"C:\Users\x"#))
    }

    @Test("multi-line basic string")
    func multilineBasic() throws {
        let input = """
        q = \"\"\"
        line one
        line two\"\"\"
        """
        let v = try TOML.parse(input)
        #expect(value(entries(v), for: "q") == .string("line one\nline two"))
    }

    @Test("multi-line literal string")
    func multilineLiteral() throws {
        let input = "q = '''\nfirst\nsecond'''"
        let v = try TOML.parse(input)
        #expect(value(entries(v), for: "q") == .string("first\nsecond"))
    }

    @Test("line-ending backslash trim in multi-line basic")
    func lineEndingBackslash() throws {
        let input = """
        q = \"\"\"\\
        hello \\
            world\"\"\"
        """
        let v = try TOML.parse(input)
        if case .string(let s) = value(entries(v), for: "q")! {
            #expect(s == "hello world")
        } else {
            Issue.record("expected string")
        }
    }
}

@Suite("Parser — arrays / inline tables")
struct ParserArrayTableTests {
    @Test("inline array of integers")
    func intArray() throws {
        let v = try TOML.parse("a = [1, 2, 3]")
        #expect(value(entries(v), for: "a") == .array([.integer(1), .integer(2), .integer(3)]))
    }

    @Test("nested inline arrays")
    func nestedArray() throws {
        let v = try TOML.parse("a = [[1, 2], [3, 4]]")
        #expect(value(entries(v), for: "a") == .array([
            .array([.integer(1), .integer(2)]),
            .array([.integer(3), .integer(4)]),
        ]))
    }

    @Test("inline table")
    func inlineTable() throws {
        let v = try TOML.parse("p = { x = 1, y = 2 }")
        if case .table(let inner) = value(entries(v), for: "p")! {
            #expect(value(inner, for: "x") == .integer(1))
            #expect(value(inner, for: "y") == .integer(2))
        } else {
            Issue.record("expected table")
        }
    }

    @Test("inline table with dotted key")
    func inlineDotted() throws {
        let v = try TOML.parse("p = { a.b = 1 }")
        if case .table(let inner) = value(entries(v), for: "p")!,
           case .table(let nested) = value(inner, for: "a")! {
            #expect(value(nested, for: "b") == .integer(1))
        } else {
            Issue.record("expected nested table")
        }
    }

    @Test("trailing comma in array allowed")
    func trailingComma() throws {
        let v = try TOML.parse("a = [1, 2, 3,]")
        #expect(value(entries(v), for: "a") == .array([.integer(1), .integer(2), .integer(3)]))
    }

    @Test("multi-line array with comments and newlines")
    func multilineArray() throws {
        let v = try TOML.parse("""
        a = [
          1,    # one
          2,
          3,
        ]
        """)
        #expect(value(entries(v), for: "a") == .array([.integer(1), .integer(2), .integer(3)]))
    }
}

@Suite("Parser — tables")
struct ParserTablesTests {
    @Test("simple table header")
    func simpleHeader() throws {
        let v = try TOML.parse("""
        [server]
        host = "localhost"
        port = 8080
        """)
        if case .table(let inner) = value(entries(v), for: "server")! {
            #expect(value(inner, for: "host") == .string("localhost"))
            #expect(value(inner, for: "port") == .integer(8080))
        } else {
            Issue.record()
        }
    }

    @Test("nested table header [a.b.c]")
    func nestedHeader() throws {
        let v = try TOML.parse("""
        [a.b.c]
        x = 1
        """)
        if case .table(let a) = value(entries(v), for: "a")!,
           case .table(let b) = value(a, for: "b")!,
           case .table(let c) = value(b, for: "c")! {
            #expect(value(c, for: "x") == .integer(1))
        } else {
            Issue.record()
        }
    }

    @Test("dotted key creates nested tables")
    func dottedKey() throws {
        let v = try TOML.parse("a.b.c = 42")
        if case .table(let a) = value(entries(v), for: "a")!,
           case .table(let b) = value(a, for: "b")! {
            #expect(value(b, for: "c") == .integer(42))
        } else {
            Issue.record()
        }
    }

    @Test("array of tables [[items]]")
    func arrayOfTables() throws {
        let v = try TOML.parse("""
        [[items]]
        name = "first"

        [[items]]
        name = "second"
        """)
        if case .array(let arr) = value(entries(v), for: "items")! {
            #expect(arr.count == 2)
            if case .table(let first) = arr[0] {
                #expect(value(first, for: "name") == .string("first"))
            }
            if case .table(let second) = arr[1] {
                #expect(value(second, for: "name") == .string("second"))
            }
        } else {
            Issue.record()
        }
    }
}

@Suite("Parser — datetimes (preserved as raw string per RFC-0010)")
struct ParserDatetimeTests {
    @Test("offset datetime")
    func offsetDatetime() throws {
        let v = try TOML.parse(#"d = 1979-05-27T07:32:00Z"#)
        #expect(value(entries(v), for: "d") == .datetime("1979-05-27T07:32:00Z"))
    }

    @Test("offset datetime with explicit offset")
    func offsetExplicit() throws {
        let v = try TOML.parse(#"d = 1979-05-27T00:32:00-07:00"#)
        #expect(value(entries(v), for: "d") == .datetime("1979-05-27T00:32:00-07:00"))
    }

    @Test("local datetime (no offset)")
    func localDatetime() throws {
        let v = try TOML.parse("d = 1979-05-27T07:32:00")
        #expect(value(entries(v), for: "d") == .datetime("1979-05-27T07:32:00"))
    }

    @Test("local date")
    func localDate() throws {
        let v = try TOML.parse("d = 1979-05-27")
        #expect(value(entries(v), for: "d") == .datetime("1979-05-27"))
    }

    @Test("local time")
    func localTime() throws {
        let v = try TOML.parse("d = 07:32:00")
        #expect(value(entries(v), for: "d") == .datetime("07:32:00"))
    }
}

@Suite("Parser — error paths")
struct ParserErrorTests {
    @Test("unterminated basic string")
    func unterminated() {
        #expect(throws: (any Error).self) {
            try TOML.parse(#"a = "open"#)
        }
    }

    @Test("invalid escape sequence")
    func invalidEscape() {
        #expect(throws: (any Error).self) {
            try TOML.parse(#"a = "\q""#)
        }
    }

    @Test("duplicate top-level key")
    func duplicateKey() {
        #expect(throws: (any Error).self) {
            try TOML.parse("""
            a = 1
            a = 2
            """)
        }
    }

    @Test("missing equals")
    func missingEquals() {
        #expect(throws: (any Error).self) {
            try TOML.parse("a 1")
        }
    }
}

@Suite("Round-trip — parse + serialize")
struct RoundTripTests {
    @Test("simple flat document")
    func simpleFlat() throws {
        let original = """
        name = "alice"
        age = 30
        active = true
        """
        let parsed = try TOML.parse(original)
        let serialized = TOML.serialize(parsed)
        let reparsed = try TOML.parse(serialized)
        #expect(parsed == reparsed)
    }

    @Test("nested table")
    func nestedTable() throws {
        let original = """
        title = "demo"

        [server]
        host = "localhost"
        port = 8080
        """
        let parsed = try TOML.parse(original)
        let serialized = TOML.serialize(parsed)
        let reparsed = try TOML.parse(serialized)
        #expect(parsed == reparsed)
    }

    @Test("array of tables")
    func arrayOfTables() throws {
        let original = """
        [[products]]
        name = "Hammer"
        sku = 738594937

        [[products]]
        name = "Nail"
        sku = 284758393
        color = "gray"
        """
        let parsed = try TOML.parse(original)
        let serialized = TOML.serialize(parsed)
        let reparsed = try TOML.parse(serialized)
        #expect(parsed == reparsed)
    }

    @Test("scalar arrays + inline tables")
    func mixedScalars() throws {
        let original = """
        ports = [80, 443, 8080]
        coords = { x = 1, y = 2 }
        """
        let parsed = try TOML.parse(original)
        let serialized = TOML.serialize(parsed)
        let reparsed = try TOML.parse(serialized)
        #expect(parsed == reparsed)
    }

    @Test("datetimes preserve raw form")
    func datetimes() throws {
        let original = """
        offset = 1979-05-27T07:32:00Z
        local = 1979-05-27T07:32:00
        date = 1979-05-27
        time = 07:32:00
        """
        let parsed = try TOML.parse(original)
        let serialized = TOML.serialize(parsed)
        let reparsed = try TOML.parse(serialized)
        #expect(parsed == reparsed)
    }
}

@Suite("End-to-end — realistic TOML")
struct EndToEndTests {
    @Test("Cargo.toml-style fragment")
    func cargoStyle() throws {
        let input = """
        # Project metadata
        [package]
        name = "demo"
        version = "0.1.0"
        edition = "2021"

        [dependencies]
        serde = { version = "1.0", features = ["derive"] }
        tokio = "1.35"

        [[bin]]
        name = "demo-cli"
        path = "src/cli.rs"

        [[bin]]
        name = "demo-server"
        path = "src/server.rs"
        """
        let v = try TOML.parse(input)
        let e = entries(v)

        if case .table(let pkg) = value(e, for: "package")! {
            #expect(value(pkg, for: "name") == .string("demo"))
            #expect(value(pkg, for: "version") == .string("0.1.0"))
        }

        if case .array(let bins) = value(e, for: "bin")! {
            #expect(bins.count == 2)
        }
    }
}
