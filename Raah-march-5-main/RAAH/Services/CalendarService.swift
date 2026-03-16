import Foundation
import EventKit

struct CalendarEvent {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?

    var minutesFromNow: Int { Int(startDate.timeIntervalSinceNow / 60) }
    var durationMinutes: Int { Int(endDate.timeIntervalSince(startDate) / 60) }
}

final class CalendarService {

    private let store = EKEventStore()

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            print("[Calendar] Permission request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Fetch

    /// Returns all non-all-day events for today (midnight → midnight), sorted by start time.
    func todaysEvents() -> [CalendarEvent] {
        guard isAuthorized else { return [] }

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarEvent(
                title: $0.title ?? "Event",
                startDate: $0.startDate,
                endDate: $0.endDate,
                location: $0.location
            )}
            .sorted { $0.startDate < $1.startDate }
    }

    /// Returns non-all-day events starting within the next `hours` hours, sorted by start time.
    func upcomingEvents(hours: Int = 6) -> [CalendarEvent] {
        guard isAuthorized else { return [] }

        let now = Date()
        guard let end = Calendar.current.date(byAdding: .hour, value: hours, to: now) else { return [] }

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { CalendarEvent(
                title: $0.title ?? "Event",
                startDate: $0.startDate,
                endDate: $0.endDate,
                location: $0.location
            )}
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Formatted string for system prompt

    func systemPromptFragment(timeZone: TimeZone) -> String? {
        // Use full day so a 4 PM meeting is visible even if it's 8 AM
        let events = todaysEvents()
        guard !events.isEmpty else { return nil }

        let fmt = DateFormatter()
        fmt.timeZone = timeZone
        fmt.timeStyle = .short
        fmt.dateStyle = .none

        let lines = events.map { event -> String in
            let mins = event.minutesFromNow
            let timeStr = fmt.string(from: event.startDate)
            let timeUntil: String
            if mins < 0 {
                timeUntil = "in progress"
            } else if mins < 60 {
                timeUntil = "in \(mins) min"
            } else {
                let h = mins / 60
                let m = mins % 60
                timeUntil = m > 0 ? "in \(h)h \(m)m" : "in \(h)h"
            }
            var line = "- \(event.title) at \(timeStr) (\(timeUntil), \(event.durationMinutes) min long)"
            if let loc = event.location, !loc.isEmpty { line += " @ \(loc)" }
            return line
        }

        return "TODAY'S SCHEDULE:\n\(lines.joined(separator: "\n"))"
    }
}
