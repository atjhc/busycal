import Foundation
import EventKit

// CONFIGURATION — all values read from environment variables with sensible defaults
private let env = ProcessInfo.processInfo.environment

let SOURCE_CALENDAR_NAME = env["BUSYCAL_SOURCE_CALENDAR"] ?? "Home"
let SOURCE_ACCOUNT_NAME = env["BUSYCAL_SOURCE_ACCOUNT"]
let DESTINATION_CALENDAR_NAME = env["BUSYCAL_DESTINATION_CALENDAR"] ?? "Busy"
let DESTINATION_ACCOUNT_NAME = env["BUSYCAL_DESTINATION_ACCOUNT"]
let BUSY_TITLE = env["BUSYCAL_TITLE"] ?? "Busy"
let INCLUDE_ALL_DAY_EVENTS = env["BUSYCAL_INCLUDE_ALL_DAY"] == "true"
let FILTER_WEEKENDS = env["BUSYCAL_FILTER_WEEKENDS"].map { $0 == "true" } ?? true
let FILTER_NON_WORK_HOURS = env["BUSYCAL_FILTER_NON_WORK_HOURS"].map { $0 == "true" } ?? true
let WORK_START_HOUR = env["BUSYCAL_WORK_START_HOUR"].flatMap(Int.init) ?? 8
let WORK_END_HOUR = env["BUSYCAL_WORK_END_HOUR"].flatMap(Int.init) ?? 18

class CalendarBusyCal {
    private let eventStore = EKEventStore()
    private var sourceCalendar: EKCalendar?
    private var destinationCalendar: EKCalendar?
    
    func run() {
        log("🚀 Starting BusyCal...")
        
        // Request calendar access
        requestCalendarAccess { [weak self] granted in
            if granted {
                self?.performSync()
            } else {
                self?.log("❌ Calendar access denied. Please grant access in System Preferences > Privacy & Security > Calendars")
                exit(1)
            }
        }
        
        // Keep the program running until async operations complete
        RunLoop.main.run()
    }
    
    private func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized, .fullAccess:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .writeOnly:
            // Write-only access is not sufficient for our use case (we need to read events)
            completion(false)
        case .notDetermined:
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.log("❌ Calendar access error: \(error.localizedDescription)")
                        }
                        completion(granted)
                    }
                }
            } else {
                eventStore.requestAccess(to: .event) { [weak self] granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self?.log("❌ Calendar access error: \(error.localizedDescription)")
                        }
                        completion(granted)
                    }
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    private func performSync() {
        // Find source and destination calendars
        guard let sourceCalendar = findCalendar(named: SOURCE_CALENDAR_NAME, account: SOURCE_ACCOUNT_NAME) else {
            log("❌ Could not find source calendar '\(SOURCE_CALENDAR_NAME)'" + (SOURCE_ACCOUNT_NAME.map { " in account '\($0)'" } ?? ""))
            exit(1)
        }

        guard let destinationCalendar = findCalendar(named: DESTINATION_CALENDAR_NAME, account: DESTINATION_ACCOUNT_NAME) else {
            log("❌ Could not find destination calendar '\(DESTINATION_CALENDAR_NAME)'" + (DESTINATION_ACCOUNT_NAME.map { " in account '\($0)'" } ?? ""))
            exit(1)
        }
        
        self.sourceCalendar = sourceCalendar
        self.destinationCalendar = destinationCalendar
        
        log("✓ Found calendars: '\(SOURCE_CALENDAR_NAME)' → '\(DESTINATION_CALENDAR_NAME)'")
        
        // Set date range (30 days back to 90 days forward)
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let endDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())!
        
        log("📅 Syncing events from \(formatDate(startDate)) to \(formatDate(endDate))")
        
        // Get source events (including recurring event instances)
        let allSourceEvents = getEventsIncludingRecurring(from: sourceCalendar, startDate: startDate, endDate: endDate)
        
        // Apply filters incrementally to get accurate per-filter counts
        var remaining = allSourceEvents
        var allDayFiltered = 0
        var weekendFiltered = 0
        var nonWorkHoursFiltered = 0

        if !INCLUDE_ALL_DAY_EVENTS {
            let before = remaining.count
            remaining = remaining.filter { !$0.isAllDay }
            allDayFiltered = before - remaining.count
        }
        if FILTER_WEEKENDS {
            let before = remaining.count
            remaining = remaining.filter { !isWeekend($0.startDate) }
            weekendFiltered = before - remaining.count
        }
        if FILTER_NON_WORK_HOURS {
            let before = remaining.count
            remaining = remaining.filter { isWithinWorkingHours($0) }
            nonWorkHoursFiltered = before - remaining.count
        }

        let sourceEvents = remaining
        let totalFilteredCount = allSourceEvents.count - sourceEvents.count

        log("📋 Found \(allSourceEvents.count) source events (including recurring instances)")
        if totalFilteredCount > 0 {
            log("🚫 Filtered out \(totalFilteredCount) events:")
            if allDayFiltered > 0 {
                log("   • \(allDayFiltered) all-day events")
            }
            if weekendFiltered > 0 {
                log("   • \(weekendFiltered) weekend events")
            }
            if nonWorkHoursFiltered > 0 {
                log("   • \(nonWorkHoursFiltered) events outside work hours (\(WORK_START_HOUR):00-\(WORK_END_HOUR):00)")
            }
        }
        log("📋 Processing \(sourceEvents.count) events for sync")
        
        // Get existing destination events
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [destinationCalendar])
        let destinationEvents = eventStore.events(matching: predicate)
        log("📋 Found \(destinationEvents.count) existing destination events")
        
        // Track which destination events we've matched
        var matchedDestinationEvents = Set<EKEvent>()
        var createdCount = 0
        var updatedCount = 0
        
        // Process each source event
        for sourceEvent in sourceEvents {
            let eventStartDate = sourceEvent.startDate
            let eventEndDate = sourceEvent.endDate
            let isAllDay = sourceEvent.isAllDay
            
            // Look for existing matching event in destination calendar
            var foundMatch = false
            for destinationEvent in destinationEvents {
                if destinationEvent.startDate == eventStartDate && destinationEvent.endDate == eventEndDate {
                    foundMatch = true
                    matchedDestinationEvents.insert(destinationEvent)
                    
                    // Update existing event if needed
                    let notes = destinationEvent.notes ?? ""
                    let location = destinationEvent.location ?? ""
                    if destinationEvent.title != BUSY_TITLE || !notes.isEmpty || !location.isEmpty {
                        destinationEvent.title = BUSY_TITLE
                        destinationEvent.notes = ""
                        destinationEvent.location = ""
                        
                        do {
                            try eventStore.save(destinationEvent, span: .thisEvent)
                            updatedCount += 1
                        } catch {
                            log("⚠️ Failed to update event: \(error.localizedDescription)")
                        }
                    }
                    break
                }
            }
            
            // Create new event if no match found
            if !foundMatch {
                let newEvent = EKEvent(eventStore: eventStore)
                newEvent.calendar = destinationCalendar
                newEvent.title = BUSY_TITLE
                newEvent.startDate = eventStartDate
                newEvent.endDate = eventEndDate
                newEvent.isAllDay = isAllDay
                newEvent.notes = ""
                newEvent.location = ""
                
                do {
                    try eventStore.save(newEvent, span: .thisEvent)
                    createdCount += 1
                } catch {
                    log("⚠️ Failed to create event: \(error.localizedDescription)")
                }
            }
        }
        
        // Remove destination events that no longer have corresponding source events
        var deletedCount = 0
        for destinationEvent in destinationEvents {
            guard !matchedDestinationEvents.contains(destinationEvent) else { continue }
            do {
                try eventStore.remove(destinationEvent, span: .thisEvent)
                deletedCount += 1
            } catch {
                log("⚠️ Failed to delete event: \(error.localizedDescription)")
            }
        }
        
        log("✅ Sync complete: Created \(createdCount), Updated \(updatedCount), Deleted \(deletedCount)")
        exit(0)
    }
    
    private func findCalendar(named name: String, account: String? = nil) -> EKCalendar? {
        let matches = eventStore.calendars(for: .event).filter { $0.title == name }
        guard let account else { return matches.first }
        return matches.first { $0.source.title == account }
    }
    
    private func getEventsIncludingRecurring(from calendar: EKCalendar, startDate: Date, endDate: Date) -> [EKEvent] {
        // EventKit automatically handles recurring events when we use predicateForEvents
        // This will return individual instances of recurring events within the date range
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: [calendar])
        return eventStore.events(matching: predicate)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
    
    private func log(_ message: String) {
        print("[\(timestamp())] \(message)")
    }
    
    private func isWeekend(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
    }
    
    private func isWithinWorkingHours(_ event: EKEvent) -> Bool {
        guard !event.isAllDay else { return true }

        let calendar = Calendar.current
        let startHour = calendar.component(.hour, from: event.startDate)
        let endHour = calendar.component(.hour, from: event.endDate)
        let endMinute = calendar.component(.minute, from: event.endDate)

        let endsAfterWorkEnd = endHour > WORK_END_HOUR
            || (endHour == WORK_END_HOUR && endMinute > 0)

        return startHour >= WORK_START_HOUR && !endsAfterWorkEnd
    }
}

// Main execution
let busyCal = CalendarBusyCal()
busyCal.run()
