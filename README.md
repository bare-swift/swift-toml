# swift-toml

TOML 1.0 parser + serializer — Sendable, Foundation-free.

Part of the [bare-swift](https://github.com/bare-swift) ecosystem.

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/bare-swift/swift-toml.git", from: "0.1.0")
```

Then depend on the `TOML` product:

```swift
.product(name: "TOML", package: "swift-toml")
```

## Usage

```swift
import TOML

let doc = """
# Project metadata
[package]
name = "demo"
version = "0.1.0"

[dependencies]
serde = { version = "1.0", features = ["derive"] }

[[bin]]
name = "demo-cli"
path = "src/cli.rs"
"""

let parsed = try TOML.parse(doc)
let roundTrip = TOML.serialize(parsed)
```

## Scope

`swift-toml` ships v0.1 with full TOML 1.0 support:

- `TOMLValue` value type covering all 6 TOML types (`string`, `integer`, `float`, `bool`, `datetime`, `array`, `table`).
- `TOMLValue.Entry` for ordered key/value pairs (insertion order preserved for round-trip).
- `TOML.parse(_:) throws(TOMLError) -> TOMLValue` — full TOML 1.0 grammar:
  - Bare and quoted keys, dotted keys (`a.b.c = 1`).
  - Table headers (`[a.b.c]`) and arrays of tables (`[[a]]`).
  - Inline tables (`{ x = 1, y = 2 }`) including dotted-key inline form.
  - Inline arrays (multi-line tolerant; trailing-comma allowed).
  - Strings: basic, multi-line basic (with line-ending backslash trim), literal, multi-line literal; `\u`/`\U` Unicode escapes.
  - Integers in decimal, hex (`0x`), octal (`0o`), binary (`0b`); underscore separators.
  - Floats including `inf` / `-inf` / `nan` / `+nan`.
  - Booleans (lowercase).
  - All four datetime forms (offset datetime, local datetime, local date, local time).
- `TOML.serialize(_:) -> String` — round-trips parsed input; emits scalar key/value pairs first then nested table headers / arrays-of-tables in document order.
- `TOMLError` typed-throws enum (10 cases including line/column information).

Datetime values are preserved as their raw text-form string per [RFC-0010](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0010-foundation-free-date-time-policy.md); typed datetime accessors are deferred to v0.2 once the `swift-time` foundation package ships.

Out of scope for v0.1:

- TOML 1.1 (in-progress spec). Watch RFC-0010 / Phase 6 for adoption.
- `Codable` bridging — deliberately excluded.
- Schema validation / decode-into-Codable.
- Comment-preserving round-trip. v0.1 strips comments on serialize; preservation is v0.2.

## Documentation

Full DocC documentation: <https://bare-swift.github.io/swift-toml/>

## Source

No upstream Rust crate; this is a native bare-swift package implementing the TOML 1.0 spec directly.

## License

Apache 2.0 with LLVM exception. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
