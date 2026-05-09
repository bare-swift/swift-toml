// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Sendable, Foundation-free TOML 1.0 parser + serializer.
///
/// TOML spec: <https://toml.io/en/v1.0.0>.
///
/// The top-level value of a TOML document is always a table. ``parse(_:)``
/// returns a ``TOMLValue`` whose case is ``TOMLValue/table(_:)``;
/// ``serialize(_:)`` round-trips that value back to TOML text.
///
/// Datetime values are preserved as their raw RFC 3339 / TOML datetime
/// string per [RFC-0010](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0010-foundation-free-date-time-policy.md);
/// typed datetime accessors are deferred to v0.2 once the `swift-time`
/// foundation package ships.
public enum TOML: Sendable {
    /// Parse a TOML 1.0 document. Returns a ``TOMLValue/table(_:)`` carrying
    /// the document's top-level keys and any nested tables.
    public static func parse(_ input: String) throws(TOMLError) -> TOMLValue {
        try Parser.parse(input)
    }

    /// Serialize a ``TOMLValue`` (must be a top-level `.table`) back to TOML
    /// text. Emits scalar key/value pairs first, then nested table headers
    /// in document order; preserves insertion order from the input.
    public static func serialize(_ value: TOMLValue) -> String {
        Serializer.serialize(value)
    }
}
