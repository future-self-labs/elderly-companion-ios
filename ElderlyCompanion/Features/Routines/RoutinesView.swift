import SwiftUI

struct RoutinesView: View {
    @State private var viewModel = RoutinesViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.xl) {
                // Medication reminders
                medicationSection

                // Daily check-in
                dailyCheckInSection

                // Weekly rituals
                weeklyRitualsSection
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $viewModel.showAddMedication) {
            AddMedicationView(onSave: { medication in
                viewModel.addMedication(medication)
            })
        }
        .sheet(isPresented: $viewModel.showAddRitual) {
            AddRitualView(onSave: { ritual in
                viewModel.addRitual(ritual)
            })
        }
    }

    // MARK: - Medication Section

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
            HStack {
                CalmCardHeader("Medications", icon: "pills.fill", subtitle: "Daily medication reminders")
                Spacer()
                Button {
                    viewModel.showAddMedication = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.companionPrimary)
                }
            }

            if viewModel.medications.isEmpty {
                CalmCard {
                    HStack {
                        Image(systemName: "pills")
                            .foregroundStyle(Color.companionTextTertiary)
                        Text("No medications added yet")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextTertiary)
                    }
                }
            } else {
                ForEach(viewModel.medications) { medication in
                    MedicationRow(medication: medication)
                }
            }
        }
    }

    // MARK: - Daily Check-In Section

    private var dailyCheckInSection: some View {
        CalmCard {
            VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                CalmCardHeader("Daily Check-In", icon: "sun.max.fill")

                Toggle(isOn: $viewModel.dailyCheckIn.enabled) {
                    Text("Enable daily check-in")
                        .font(.companionBody)
                }
                .tint(Color.companionPrimary)

                if viewModel.dailyCheckIn.enabled {
                    Divider()

                    DatePicker("Time", selection: $viewModel.dailyCheckIn.time, displayedComponents: .hourAndMinute)
                        .font(.companionBody)

                    Picker("Format", selection: $viewModel.dailyCheckIn.format) {
                        ForEach(DailyCheckIn.CheckInFormat.allCases, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(isOn: $viewModel.dailyCheckIn.callIfNoActivity) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Call if no activity")
                                .font(.companionBody)
                            Text("Noah will call if you haven't been active today")
                                .font(.companionCaption)
                                .foregroundStyle(Color.companionTextSecondary)
                        }
                    }
                    .tint(Color.companionPrimary)
                }
            }
        }
    }

    // MARK: - Weekly Rituals Section

    private var weeklyRitualsSection: some View {
        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
            HStack {
                CalmCardHeader("Weekly Rituals", icon: "repeat", subtitle: "Recurring activities")
                Spacer()
                Button {
                    viewModel.showAddRitual = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.companionPrimary)
                }
            }

            if viewModel.rituals.isEmpty {
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.sm) {
                        Text("No rituals yet")
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextTertiary)

                        Text("Examples: \"Memory Monday\", \"Call your sister\", \"Garden check\"")
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextTertiary)
                    }
                }
            } else {
                ForEach(viewModel.rituals) { ritual in
                    RitualRow(ritual: ritual)
                }
            }
        }
    }
}

// MARK: - Medication Row

struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        CalmCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)

                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Text(medication.time.formatted(.dateTime.hour().minute()))
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)

                        Text(medication.frequency.label)
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }

                Spacer()

                Image(systemName: medication.notificationMethod.iconName)
                    .foregroundStyle(Color.companionPrimary)
            }
        }
    }
}

// MARK: - Ritual Row

struct RitualRow: View {
    let ritual: WeeklyRitual

    private let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        CalmCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ritual.name)
                        .font(.companionBody)
                        .foregroundStyle(Color.companionTextPrimary)

                    Text("\(dayNames[min(ritual.dayOfWeek, 7)]) at \(ritual.time.formatted(.dateTime.hour().minute()))")
                        .font(.companionCaption)
                        .foregroundStyle(Color.companionTextSecondary)
                }

                Spacer()

                Image(systemName: ritual.enabled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(ritual.enabled ? Color.companionPrimary : Color.companionTextTertiary)
            }
        }
    }
}

// MARK: - Add Medication View

struct AddMedicationView: View {
    let onSave: (Medication) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var time = Date()
    @State private var frequency: Medication.MedicationFrequency = .daily
    @State private var method: Medication.NotificationMethod = .push
    @State private var escalate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    CompanionTextField("Medication name", text: $name, icon: "pills.fill")

                    CalmCard {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .font(.companionBody)
                    }

                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            Text("Frequency")
                                .font(.companionBody)
                            Picker("Frequency", selection: $frequency) {
                                ForEach(Medication.MedicationFrequency.allCases, id: \.self) { freq in
                                    Text(freq.label).tag(freq)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            Text("Remind via")
                                .font(.companionBody)
                            Picker("Method", selection: $method) {
                                ForEach(Medication.NotificationMethod.allCases, id: \.self) { m in
                                    Text(m.label).tag(m)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    CalmCard {
                        Toggle(isOn: $escalate) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Escalate if ignored")
                                    .font(.companionBody)
                                Text("Notify family if reminder is not acknowledged")
                                    .font(.companionCaption)
                                    .foregroundStyle(Color.companionTextSecondary)
                            }
                        }
                        .tint(Color.companionPrimary)
                    }
                }
                .padding(CompanionTheme.Spacing.lg)
            }
            .background(Color.companionBackground)
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let medication = Medication(
                            id: UUID().uuidString,
                            name: name,
                            time: time,
                            frequency: frequency,
                            notificationMethod: method,
                            escalateIfIgnored: escalate
                        )
                        onSave(medication)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.companionPrimary)
    }
}

// MARK: - Add Ritual View

struct AddRitualView: View {
    let onSave: (WeeklyRitual) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var dayOfWeek = 2 // Monday
    @State private var time = Date()

    private let days = [
        (1, "Sunday"), (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"),
        (5, "Thursday"), (6, "Friday"), (7, "Saturday")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    CompanionTextField("Ritual name", text: $name, icon: "repeat")

                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            Text("Day of the week")
                                .font(.companionBody)

                            Picker("Day", selection: $dayOfWeek) {
                                ForEach(days, id: \.0) { day in
                                    Text(day.1).tag(day.0)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 120)
                        }
                    }

                    CalmCard {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                            .font(.companionBody)
                    }
                }
                .padding(CompanionTheme.Spacing.lg)
            }
            .background(Color.companionBackground)
            .navigationTitle("Add Ritual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ritual = WeeklyRitual(
                            id: UUID().uuidString,
                            name: name,
                            dayOfWeek: dayOfWeek,
                            time: time,
                            enabled: true
                        )
                        onSave(ritual)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.companionPrimary)
    }
}
