import SwiftUI

struct ScheduledCallsView: View {
    @State private var viewModel = ScheduledCallsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: CompanionTheme.Spacing.lg) {
                // Info card
                CalmCard {
                    VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                        CalmCardHeader("Proactive Calls", icon: "phone.arrow.up.right.fill", subtitle: "Noah calls you automatically")

                        Text("Set up times for Noah to call you for medication reminders, daily check-ins, or just a friendly chat.")
                            .font(.companionBodySecondary)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }

                // Existing scheduled calls
                if !viewModel.scheduledCalls.isEmpty {
                    VStack(spacing: CompanionTheme.Spacing.md) {
                        ForEach(viewModel.scheduledCalls) { call in
                            ScheduledCallRow(call: call, onToggle: { enabled in
                                viewModel.toggleCall(call, enabled: enabled)
                            })
                        }
                    }
                }

                // Quick-add buttons
                VStack(spacing: CompanionTheme.Spacing.md) {
                    LargeButton("Add Medication Reminder", icon: "pills.fill", style: .outline) {
                        viewModel.showAddCall = true
                        viewModel.newCallType = .medication
                    }

                    LargeButton("Add Daily Check-In", icon: "sun.max.fill", style: .outline) {
                        viewModel.showAddCall = true
                        viewModel.newCallType = .checkin
                    }

                    LargeButton("Add Friendly Chat", icon: "bubble.left.and.bubble.right.fill", style: .outline) {
                        viewModel.showAddCall = true
                        viewModel.newCallType = .chat
                    }
                }
            }
            .padding(CompanionTheme.Spacing.lg)
        }
        .background(Color.companionBackground)
        .navigationTitle("Scheduled Calls")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $viewModel.showAddCall) {
            AddScheduledCallView(
                type: viewModel.newCallType,
                onSave: { call in
                    viewModel.addCall(call)
                }
            )
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong.")
        }
        .task {
            await viewModel.loadCalls()
        }
    }
}

// MARK: - Scheduled Call Row

struct ScheduledCallRow: View {
    let call: APIClient.ScheduledCallRecord
    let onToggle: (Bool) -> Void

    @State private var isEnabled: Bool

    init(call: APIClient.ScheduledCallRecord, onToggle: @escaping (Bool) -> Void) {
        self.call = call
        self.onToggle = onToggle
        self._isEnabled = State(initialValue: call.enabled)
    }

    var body: some View {
        CalmCard {
            HStack {
                VStack(alignment: .leading, spacing: CompanionTheme.Spacing.xs) {
                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Image(systemName: iconForType(call.type))
                            .foregroundStyle(Color.companionPrimary)
                        Text(call.title)
                            .font(.companionBody)
                            .foregroundStyle(Color.companionTextPrimary)
                    }

                    HStack(spacing: CompanionTheme.Spacing.sm) {
                        Text(call.time)
                            .font(.companionHeadline)
                            .foregroundStyle(Color.companionTextPrimary)

                        Text(daysLabel(call.days))
                            .font(.companionCaption)
                            .foregroundStyle(Color.companionTextSecondary)
                    }
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(Color.companionPrimary)
                    .onChange(of: isEnabled) { _, newValue in
                        onToggle(newValue)
                    }
            }
        }
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "medication": return "pills.fill"
        case "checkin": return "sun.max.fill"
        case "chat": return "bubble.left.and.bubble.right.fill"
        default: return "phone.fill"
        }
    }

    private func daysLabel(_ days: [Int]) -> String {
        if days.count == 7 { return "Every day" }
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.map { dayNames[$0] }.joined(separator: ", ")
    }
}

// MARK: - Add Scheduled Call View

struct AddScheduledCallView: View {
    let type: ScheduledCallType
    let onSave: (APIClient.ScheduledCallRequest) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var time = Calendar.current.date(from: DateComponents(hour: 10, minute: 0)) ?? Date()
    @State private var selectedDays: Set<Int> = [0, 1, 2, 3, 4, 5, 6]
    @State private var customMessage = ""

    private let dayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    // Title
                    CompanionTextField(titlePlaceholder, text: $title, icon: iconForType)

                    // Time picker
                    CalmCard {
                        DatePicker("Call time", selection: $time, displayedComponents: .hourAndMinute)
                            .font(.companionBody)
                    }

                    // Days selector
                    CalmCard {
                        VStack(alignment: .leading, spacing: CompanionTheme.Spacing.md) {
                            Text("Repeat on")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextPrimary)

                            HStack(spacing: CompanionTheme.Spacing.sm) {
                                ForEach(0..<7, id: \.self) { day in
                                    Button {
                                        if selectedDays.contains(day) {
                                            selectedDays.remove(day)
                                        } else {
                                            selectedDays.insert(day)
                                        }
                                    } label: {
                                        Text(dayLabels[day])
                                            .font(.companionLabel)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, CompanionTheme.Spacing.sm)
                                            .background(
                                                selectedDays.contains(day)
                                                    ? Color.companionPrimary
                                                    : Color.companionSurfaceSecondary
                                            )
                                            .foregroundStyle(
                                                selectedDays.contains(day)
                                                    ? .white
                                                    : Color.companionTextSecondary
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: CompanionTheme.Radius.sm))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Custom message (for chat type)
                    if type == .chat || type == .custom {
                        CompanionTextField("Topic or message (optional)", text: $customMessage, icon: "text.bubble.fill")
                    }
                }
                .padding(CompanionTheme.Spacing.lg)
            }
            .background(Color.companionBackground)
            .navigationTitle("Schedule Call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCall()
                    }
                    .disabled(title.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .tint(Color.companionPrimary)
        .onAppear {
            title = defaultTitle
        }
    }

    private var defaultTitle: String {
        switch type {
        case .medication: return ""
        case .checkin: return "Morning Check-In"
        case .chat: return "Afternoon Chat"
        case .custom: return ""
        }
    }

    private var titlePlaceholder: String {
        switch type {
        case .medication: return "Medication name"
        case .checkin: return "Check-in name"
        case .chat: return "Chat topic"
        case .custom: return "Call title"
        }
    }

    private var iconForType: String {
        switch type {
        case .medication: return "pills.fill"
        case .checkin: return "sun.max.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .custom: return "phone.fill"
        }
    }

    private func saveCall() {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let timeStr = String(format: "%02d:%02d", hour, minute)

        let userId = UserDefaults.standard.string(forKey: "userId") ?? ""
        let phoneNumber = UserDefaults.standard.string(forKey: "userPhoneNumber") ?? ""

        let request = APIClient.ScheduledCallRequest(
            userId: userId,
            phoneNumber: phoneNumber,
            type: type.rawValue,
            title: title,
            message: customMessage.isEmpty ? nil : customMessage,
            time: timeStr,
            days: Array(selectedDays).sorted(),
            enabled: true
        )

        onSave(request)
        dismiss()
    }
}

enum ScheduledCallType: String {
    case medication
    case checkin
    case chat
    case custom
}
