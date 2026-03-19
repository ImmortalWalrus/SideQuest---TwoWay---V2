import EventKit
import Foundation
import UIKit

@Observable
class CalendarService {
    static let shared = CalendarService()
    private let store = EKEventStore()
    var isAuthorized: Bool = false
    var calendars: [EKCalendar] = []
    private let calendarName = "SideQuest"

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
            if granted { loadCalendars() }
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    func loadCalendars() {
        calendars = store.calendars(for: .event)
    }

    func sideQuestCalendar() -> EKCalendar? {
        if let existing = calendars.first(where: { $0.title == calendarName }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendarName
        cal.cgColor = UIColor.systemBlue.cgColor as CGColor
        if let source = store.defaultCalendarForNewEvents?.source {
            cal.source = source
        } else if let local = store.sources.first(where: { $0.sourceType == .local }) {
            cal.source = local
        } else {
            return store.defaultCalendarForNewEvents
        }
        do {
            try store.saveCalendar(cal, commit: true)
            loadCalendars()
            return cal
        } catch {
            return store.defaultCalendarForNewEvents
        }
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        alertOffset: TimeInterval?,
        calendar: EKCalendar?
    ) -> String? {
        guard isAuthorized else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "SideQuest: \(title)"
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar ?? sideQuestCalendar() ?? store.defaultCalendarForNewEvents
        if let offset = alertOffset {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    func deleteEvent(identifier: String) {
        guard isAuthorized, let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
    }

    func deleteEvents(identifiers: [String]) {
        for id in identifiers {
            deleteEvent(identifier: id)
        }
    }

    func createJourneyEvents(
        journey: Journey,
        quests: [Quest],
        alertOffset: TimeInterval?,
        calendar: EKCalendar?
    ) -> [String: String] {
        guard isAuthorized else { return [:] }
        var eventIds: [String: String] = [:]
        let cal = Calendar.current

        for dayOffset in 0..<journey.totalDays {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: journey.startDate)) else { continue }
            let scheduled = journey.scheduledQuestsForDate(date)
            for item in scheduled {
                guard let quest = quests.first(where: { $0.id == item.questId }) else { continue }
                let startDate: Date
                if item.hasSpecificTime, let hour = item.scheduledHour, let minute = item.scheduledMinute {
                    startDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
                } else {
                    continue
                }
                let endDate = cal.date(byAdding: .hour, value: 1, to: startDate) ?? startDate
                let key = "\(item.id)_\(dayOffset)"
                if let eventId = createEvent(title: quest.title, startDate: startDate, endDate: endDate, alertOffset: alertOffset, calendar: calendar) {
                    eventIds[key] = eventId
                }
            }
        }
        return eventIds
    }
}
