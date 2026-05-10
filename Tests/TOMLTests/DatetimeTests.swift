// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
@testable import TOML
import Time

@Suite("Datetime integration with swift-time")
struct DatetimeIntegrationTests {
    @Test("asCalendar parses an RFC 3339 datetime")
    func asCalendarOffset() throws {
        let toml = try TOML.parse("d = 2026-05-10T07:30:00Z")
        guard case .table(let entries) = toml,
              let cal = entries.first(where: { $0.key == "d" })?.value.asCalendar else {
            Issue.record(); return
        }
        #expect(cal.year == 2026 && cal.month == 5 && cal.day == 10)
        #expect(cal.hour == 7 && cal.minute == 30 && cal.second == 0)
        #expect(cal.offsetSeconds == 0)
    }

    @Test("asCalendar parses a local datetime (no offset)")
    func asCalendarLocal() throws {
        let toml = try TOML.parse("d = 2026-05-10T07:30:00")
        guard case .table(let entries) = toml,
              let cal = entries.first(where: { $0.key == "d" })?.value.asCalendar else {
            Issue.record(); return
        }
        #expect(cal.offsetSeconds == nil)
    }

    @Test("asCalendar parses local-date")
    func asCalendarDate() throws {
        let toml = try TOML.parse("d = 2026-05-10")
        guard case .table(let entries) = toml,
              let cal = entries.first(where: { $0.key == "d" })?.value.asCalendar else {
            Issue.record(); return
        }
        #expect(cal.year == 2026 && cal.month == 5 && cal.day == 10)
        #expect(cal.offsetSeconds == nil)
    }

    @Test("asCalendar returns nil for non-datetime cases")
    func asCalendarOther() {
        #expect(TOMLValue.string("hello").asCalendar == nil)
        #expect(TOMLValue.integer(42).asCalendar == nil)
    }

    @Test("asInstant returns Instant for offset datetime")
    func asInstantOffset() throws {
        let toml = try TOML.parse("d = 2026-05-10T07:30:00Z")
        guard case .table(let entries) = toml,
              let i = entries.first(where: { $0.key == "d" })?.value.asInstant else {
            Issue.record(); return
        }
        // 20583 days × 86400 + 7×3600 + 30×60 = 1_778_398_200 seconds.
        #expect(i.nanosecondsSinceEpoch == 1_778_398_200 * 1_000_000_000)
    }

    @Test("asInstant returns nil for local datetime (no offset)")
    func asInstantLocal() throws {
        let toml = try TOML.parse("d = 2026-05-10T07:30:00")
        guard case .table(let entries) = toml else { Issue.record(); return }
        let v = entries.first(where: { $0.key == "d" })!.value
        #expect(v.asInstant == nil)
    }

    @Test("datetime(from:) factory builds a datetime value")
    func factoryFromCalendar() {
        let cal = Time.Calendar(year: 2026, month: 5, day: 10, hour: 7, minute: 30, second: 0,
                                offsetSeconds: 0)
        let v = TOMLValue.datetime(from: cal)
        if case .datetime(let s) = v {
            #expect(s == "2026-05-10T07:30:00Z")
        } else {
            Issue.record("expected .datetime")
        }
    }

    @Test("round-trip Calendar → TOMLValue → Calendar")
    func roundTrip() throws {
        let original = Time.Calendar(year: 2026, month: 5, day: 10, hour: 7, minute: 30, second: 0,
                                     offsetSeconds: 0)
        let v = TOMLValue.datetime(from: original)
        guard let parsed = v.asCalendar else { Issue.record(); return }
        #expect(parsed.year == original.year)
        #expect(parsed.month == original.month)
        #expect(parsed.day == original.day)
        #expect(parsed.hour == original.hour)
        #expect(parsed.offsetSeconds == original.offsetSeconds)
    }
}
