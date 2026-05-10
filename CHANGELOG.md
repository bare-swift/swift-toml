# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-05-10

### Added
- `TOMLValue.asCalendar: Time.Calendar?` — typed view over `.datetime(String)` values. Parses the raw text via `Time.RFC3339`. Returns `nil` for non-datetime cases or strings that don't parse.
- `TOMLValue.asInstant: Time.Instant?` — typed view returning a UTC instant for offset-bearing datetimes. Local-only datetimes (no offset) return `nil` because their wall-clock-to-UTC projection is undefined.
- `TOMLValue.datetime(from: Time.Calendar) -> TOMLValue` — factory wrapping `Time.RFC3339.serialize(_:)`.
- 8 new tests covering offset / local / date-only datetime forms, `asInstant` correctness for offset-bearing values, factory output, and Calendar → TOMLValue → Calendar round-trips.

### Dependencies
- New: `swift-time` 0.1.0 — for the `Time.Calendar` and `Time.Instant` types used by the typed accessors.

### Migration
- Additive only. The `.datetime(String)` case still preserves raw text for round-trip fidelity; the new typed accessors and factory are available alongside for opt-in adoption.

## [0.1.1] - 2026-05-10

### Fixed
- Serializer now preserves insertion order across inline-table boundaries. Previously, the serializer emitted *all* nested tables as `[section]` headers at the end of each level, which silently reordered entries on parse → serialize → parse round-trip when an inline table (`key = { ... }`) appeared before a scalar at the same level. Leaf tables (those without sub-tables or arrays-of-tables) are now emitted inline at their original position; only non-leaf tables become section headers.

## [0.1.0] - 2026-05-10

### Added
- `TOMLValue` value type (Sendable, Equatable) covering all 6 TOML 1.0 types: `string`, `integer`, `float`, `bool`, `datetime`, `array`, `table`.
- `TOMLValue.Entry` for ordered key/value pairs preserving insertion order.
- `TOML.parse(_:) throws(TOMLError) -> TOMLValue` — full TOML 1.0 grammar:
  - Bare and quoted keys; dotted keys auto-create nested tables.
  - Table headers (`[a.b.c]`); arrays of tables (`[[a]]`).
  - Inline tables (`{ x = 1, y = 2 }`) including dotted-key form.
  - Inline arrays with multi-line / trailing-comma tolerance.
  - Strings: basic, multi-line basic (line-ending backslash trim), literal, multi-line literal; `\u` / `\U` Unicode escapes.
  - Integers in decimal, hex (`0x`), octal (`0o`), binary (`0b`); underscore separators.
  - Floats including `inf`, `-inf`, `nan`, `+nan`.
  - All four datetime forms (offset / local datetime / local date / local time) preserved as raw RFC 3339 text per RFC-0010.
- `TOML.serialize(_:) -> String` — round-trip serializer; emits scalars first, nested tables / arrays-of-tables after, in document order.
- `TOMLError` typed-throws enum (10 cases with line/column metadata).
- Comment recognition (parsed and skipped at scan time; not preserved in serialized output — comment-preserving round-trip is v0.2).

### Dependencies
- None at runtime. Foundation-free.

### Limitations (out of scope for v0.1)
- TOML 1.1 (in-progress spec). Watch RFC-0010 / Phase 6 for adoption.
- `Codable` bridging — deliberately excluded.
- Comment-preserving round-trip. v0.1 strips comments on serialize.
- Typed datetime accessors. Datetime values remain raw `String`; typed access lands in v0.2 once `swift-time` ships per RFC-0010.
