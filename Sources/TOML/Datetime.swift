// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Time

/// TOML datetime integration with swift-time. The TOML 1.0 datetime
/// grammar is a subset of RFC 3339, so the parsing strategy is to
/// preserve the raw text in ``TOMLValue/datetime(_:)`` and then defer
/// typed access to these helpers.
///
/// Per [RFC-0010](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0010-foundation-free-date-time-policy.md)
/// the v0.1 raw-string form remains the canonical wire-faithful
/// representation; this extension adds the typed view for consumers
/// that want to compare datetimes, do arithmetic, or convert to / from
/// other formats.
extension TOMLValue {
    /// If this value is a `.datetime(String)`, parse it as RFC 3339
    /// (TOML's datetime grammar is a subset) and return the resulting
    /// `Time.Calendar`. Returns `nil` for any other case or for
    /// strings that don't parse.
    public var asCalendar: Time.Calendar? {
        guard case .datetime(let s) = self else { return nil }
        return try? Time.RFC3339.parse(s)
    }

    /// If this value is a `.datetime(String)` carrying an offset (or `Z`),
    /// return the equivalent `Time.Instant`. Local-only datetimes (no
    /// offset) return `nil` here because their wall-clock-to-UTC
    /// projection is undefined; use ``asCalendar`` for those.
    public var asInstant: Time.Instant? {
        guard let cal = asCalendar, cal.offsetSeconds != nil else { return nil }
        return try? cal.toInstant()
    }

    /// Build a `.datetime` value from a `Time.Calendar`. The calendar's
    /// fields and offset are serialized via ``Time/RFC3339/serialize(_:)``.
    public static func datetime(from calendar: Time.Calendar) -> TOMLValue {
        .datetime(Time.RFC3339.serialize(calendar))
    }
}
