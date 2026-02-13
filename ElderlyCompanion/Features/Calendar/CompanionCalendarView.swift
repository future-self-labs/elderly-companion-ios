import SwiftUI
import EventKit

struct CompanionCalendarView: View {
    @State private var calendarService = CalendarService()
    @State private var selectedDate = Date()
    @State private var viewMode: ViewMode = .agenda
    @State private var showAddEvent = false

    enum ViewMode: String, CaseIterable {
        case month
        case agenda

        var label: String {
            switch self {
            case .month: return "Month"
            case .agenda: return "Agenda"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, CompanionTheme.Spacing.lg)
            .padding(.vertical, CompanionTheme.Spacing.md)

            // Content
            Group {
                switch viewMode {
                case .month:
                    monthView
                case .agenda:
                    agendaView
                }
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddEvent = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.companionPrimary)
                }
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventView(calendarService: calendarService)
        }
        .onAppear {
            if calendarService.authorizationStatus == .fullAccess {
                calendarService.fetchCurrentMonthEvents()
            }
        }
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: CompanionTheme.Spacing.lg) {
            // Simple month calendar
            DatePicker(
                "Select date",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .tint(Color.companionPrimary)
            .padding(.horizontal, CompanionTheme.Spacing.lg)

            // Events for selected date
            ScrollView {
                LazyVStack(spacing: CompanionTheme.Spacing.md) {
                    ForEach(eventsForSelectedDate, id: \.eventIdentifier) { event in
                        EventRow(event: event)
                    }

                    if eventsForSelectedDate.isEmpty {
                        Text("No events on this day")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextTertiary)
                            .padding(.top, CompanionTheme.Spacing.lg)
                    }
                }
                .padding(.horizontal, CompanionTheme.Spacing.lg)
            }
        }
    }

    // MARK: - Agenda View

    private var agendaView: some View {
        ScrollView {
            LazyVStack(spacing: CompanionTheme.Spacing.md) {
                if calendarService.authorizationStatus != .fullAccess {
                    // Permission required card
                    CalmCard {
                        VStack(spacing: CompanionTheme.Spacing.md) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.companionSecondary)

                            Text("Calendar access needed")
                                .font(.companionHeadline)
                                .foregroundStyle(Color.companionTextPrimary)

                            Text("Allow Noah to view your calendar to show events and send reminders.")
                                .font(.companionBodySecondary)
                                .foregroundStyle(Color.companionTextSecondary)
                                .multilineTextAlignment(.center)

                            LargeButton("Enable Calendar", icon: "calendar.badge.checkmark") {
                                Task {
                                    _ = await calendarService.requestFullAccess()
                                    calendarService.fetchCurrentMonthEvents()
                                }
                            }
                        }
                    }
                } else if calendarService.events.isEmpty {
                    VStack(spacing: CompanionTheme.Spacing.lg) {
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.companionTextTertiary)

                        Text("No upcoming events")
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text("Events from your calendar will appear here.")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextSecondary)
                        Spacer()
                    }
                } else {
                    // Upcoming events
                    ForEach(upcomingEvents, id: \.eventIdentifier) { event in
                        EventRow(event: event)
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
    }

    // MARK: - Helpers

    private var eventsForSelectedDate: [EKEvent] {
        let calendar = Calendar.current
        return calendarService.events.filter {
            calendar.isDate($0.startDate, inSameDayAs: selectedDate)
        }
    }

    private var upcomingEvents: [EKEvent] {
        calendarService.events.filter { $0.startDate >= Date() }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: EKEvent

    var body: some View {
        CalmCard {
            HStack(spacing: CompanionTheme.Spacing.md) {
                // Time indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(cgColor: event.calendar?.cgColor ?? CGColor(red: 0.42, green: 0.56, blue: 0.47, alpha: 1)))
                    .frame(width: 4, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title ?? "Untitled")
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)

                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        if event.isAllDay {
                            Text("All day")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        } else {
                            Text("\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - Add Event View

struct AddEventView: View {
    let calendarService: CalendarService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    CompanionTextField("Event title", text: $title, icon: "pencil")

                    CalmCard {
                        VStack(spacing: CompanionTheme.Spacing.md) {
                            DatePicker("Start", selection: $startDate)
                                .font(.companionBody)

                            Divider()

                            DatePicker("End", selection: $endDate)
                                .font(.companionBody)
                        }
                    }

                    CompanionTextField("Notes (optional)", text: $notes, icon: "note.text")
                }
                .padding(CompanionTheme.Spacing.lg)
            }
            .background(Color.companionBackground)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(title.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.companionPrimary)
    }

    private func saveEvent() {
        try? calendarService.addEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}
