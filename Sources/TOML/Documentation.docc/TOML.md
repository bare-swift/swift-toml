# ``TOML``

TOML 1.0 parser + serializer — Sendable, Foundation-free.

## Overview

`TOML` parses and serializes [TOML 1.0](https://toml.io/en/v1.0.0)
documents. Input is `String`; the top-level value of every document
is a ``TOMLValue/table(_:)`` carrying ordered key/value entries
(insertion order preserved for round-trip fidelity).

The parser supports the full TOML 1.0 grammar: bare and quoted keys,
dotted keys, table headers (`[a.b.c]`), arrays of tables (`[[a]]`),
inline tables (`{ x = 1, y = 2 }`), inline arrays (with multi-line
formatting and trailing-comma tolerance), basic / multi-line basic /
literal / multi-line literal strings (with `\u`/`\U` escapes and
line-ending backslash trim), integers in decimal/hex/octal/binary
(with underscore separators), floats (including `inf`, `-inf`,
`nan`, `+nan`), booleans, and the four TOML datetime forms (offset
datetime, local datetime, local date, local time).

Datetime values are preserved as their raw text-form string per
[RFC-0010](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0010-foundation-free-date-time-policy.md);
typed datetime accessors are deferred to v0.2 once the `swift-time`
foundation package ships.

```swift
import TOML

let doc = """
[package]
name = "demo"
version = "0.1.0"

[[bin]]
name = "demo-cli"
"""

let parsed = try TOML.parse(doc)
let roundTrip = TOML.serialize(parsed)
```

## Topics

### Essentials

- ``TOMLValue``
- ``TOMLError``
