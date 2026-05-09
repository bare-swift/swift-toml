// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// A parsed TOML value. Mirrors TOML 1.0's six value types.
///
/// `table` is an *ordered* list of `(key, value)` entries — TOML
/// preserves declaration order, and a `[String: TOMLValue]` would lose
/// it for serialization round-trip. Duplicate keys at the same level
/// are a parse error per TOML 1.0; the value type does not enforce
/// uniqueness, so consumers constructing values manually should keep
/// keys distinct.
///
/// `datetime` is preserved as the raw text-form string per RFC-0010.
/// Typed datetime accessors arrive in v0.2 alongside the `swift-time`
/// foundation package.
public indirect enum TOMLValue: Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case bool(Bool)
    case datetime(String)
    case array([TOMLValue])
    case table([Entry])

    public struct Entry: Sendable, Equatable {
        public var key: String
        public var value: TOMLValue

        public init(key: String, value: TOMLValue) {
            self.key = key
            self.value = value
        }
    }
}
