import SwiftUI

/// Reminders: once, daily or weekly; Noah calls or mentions it in the next conversation.
/// A memory aid, never medical care: every screen shows the disclaimer (contract v2.1 point 5).
struct RemindersListView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<[Reminder]> = .idle
    @State private var editing: ReminderEditorTarget?
    @State private var error: String?
    @State private var loadedFor: String?

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            if session.selected == nil {
                NoElderlySelectedView()
            } else {
                if !session.permissions.canEditReminders { ReadOnlyNotice() }
                ReminderDisclaimer()
                if let error { NoahNotice(kind: .error, text: error) }
                LoadableView(state: state, retry: { Task { await load() } }) { reminders in
                    if reminders.isEmpty {
                        EmptyStateView(systemImage: "bell.badge",
                                       title: "Nog geen herinneringen",
                                       message: "Noah kan een extra geheugensteuntje geven: voor een afspraak, een verjaardag, medicijnen of een vast rondje wandelen.",
                                       actionTitle: session.permissions.canEditReminders ? "Herinnering toevoegen" : nil) { editing = .new }
                    } else {
                        let active = reminders.filter(\.active).sorted { ($0.nextAt ?? .distantFuture) < ($1.nextAt ?? .distantFuture) }
                        let paused = reminders.filter { !$0.active }
                        if !active.isEmpty {
                            NoahSectionHeader(title: "Actief")
                            ForEach(active) { row($0) }
                        }
                        if !paused.isEmpty {
                            NoahSectionHeader(title: "Gepauzeerd")
                            ForEach(paused) { row($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Herinneringen")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { ElderlySwitcher() }
            ToolbarItem(placement: .navigationBarTrailing) {
                if session.permissions.canEditReminders {
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Herinnering toevoegen"))
                        .accessibilityIdentifier("reminders.add")
                }
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack { ReminderEditorView(target: target) }
                .environmentObject(session)
        }
        .refreshable { await load() }
        .task(id: session.reloadKey) { await load() }
    }

    private func row(_ reminder: Reminder) -> some View {
        Button {
            if session.permissions.canEditReminders { editing = .edit(reminder) }
        } label: {
            ReminderRow(reminder: reminder, canEdit: session.permissions.canEditReminders) { active in
                Task { await setActive(reminder, active) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!session.permissions.canEditReminders)
    }

    private func setActive(_ reminder: Reminder, _ active: Bool) async {
        var input = ReminderInput(reminder: reminder)
        input.active = active
        do {
            _ = try await session.api.updateReminder(reminderId: reminder.id, input)
            error = nil
            await load()
            session.dataChanged()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if loadedFor != id { state = .loading }
        do {
            state = .loaded(try await session.api.reminders(elderlyId: id))
            loadedFor = id
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, state.value == nil || loadedFor != id { state = .failed(apiError) }
        }
    }
}

extension ReminderInput {
    init(reminder: Reminder) {
        self.init()
        title = reminder.title
        notes = reminder.notes
        type = reminder.type == .unknown ? .overig : reminder.type
        schedule = reminder.schedule
        delivery = reminder.delivery == .unknown ? .inGesprek : reminder.delivery
        active = reminder.active
    }
}

struct ReminderRow: View {
    let reminder: Reminder
    let canEdit: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        NoahCard {
            AdaptiveStack(spacing: NoahSpacing.s) {
                NoahIconBadge(systemName: reminder.type.systemImage, tint: reminder.active ? NoahColor.accent : NoahColor.textSecondary)
                VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                    Text(verbatim: reminder.title)
                        .font(NoahFont.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: ScheduleFormatter.describe(reminder.schedule))
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.textSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    if reminder.active, let next = reminder.nextAt {
                        Text("Volgende: \(DutchFormat.upcoming(next).lowercased())")
                            .font(NoahFont.footnote)
                            .foregroundColor(NoahColor.accent)
                    }
                    HStack(spacing: NoahSpacing.xs) {
                        NoahChip(text: reminder.delivery.shortLabel, systemImage: reminder.delivery == .bellen ? "phone.fill" : "bubble.left.fill")
                        if reminder.createdBy == .noah {
                            NoahChip(text: "Door Noah", systemImage: "sparkles")
                        }
                    }
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(verbatim: notes)
                            .font(NoahFont.footnote)
                            .foregroundColor(NoahColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if canEdit {
                    Toggle("Actief", isOn: Binding(get: { reminder.active }, set: onToggle))
                        .labelsHidden()
                        .accessibilityLabel(Text("\(reminder.title) actief"))
                }
            }
        }
    }
}

/// The contract's memory-aid disclaimer, word for word.
struct ReminderDisclaimer: View {
    var body: some View {
        HStack(alignment: .top, spacing: NoahSpacing.s) {
            Image(systemName: "info.circle")
                .font(NoahFont.headline)
                .foregroundColor(NoahColor.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: ProductCopy.reminderDisclaimer)
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(NoahSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).fill(NoahColor.surfaceDeep))
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous).strokeBorder(NoahColor.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reminders.disclaimer")
    }
}

enum ReminderEditorTarget: Identifiable {
    case new
    case edit(Reminder)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let reminder): return reminder.id
        }
    }
}

struct ReminderEditorView: View {
    let target: ReminderEditorTarget

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var input = ReminderInput()
    @State private var kind: ReminderSchedule.Kind = .dagelijks
    @State private var onceDate = Date().addingTimeInterval(3600)
    @State private var time = DutchFormat.date(fromTime: "08:00")
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    @State private var error: String?
    @State private var confirmsDelete = false
    @State private var didLoad = false
    /// The short disclaimer is shown the first time a reminder is created on this phone.
    @AppStorage("reminders.createdBefore") private var createdBefore = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                if isNew && !createdBefore {
                    NoahNotice(kind: .info, text: ProductCopy.reminderDisclaimerShort)
                        .accessibilityIdentifier("reminder.firstNotice")
                }

                NoahTextField(label: "Waaraan moet Noah herinneren?", text: $input.title, prompt: "Pillen innemen")
                    .accessibilityIdentifier("reminder.title")

                NoahField(label: "Soort") {
                    FlowLayout {
                        ForEach(ReminderType.knownCases, id: \.self) { type in
                            NoahChoiceChip(title: type.label, isSelected: input.type == type) { input.type = type }
                        }
                    }
                }

                NoahField(label: "Wanneer") {
                    VStack(alignment: .leading, spacing: NoahSpacing.m) {
                        Picker("Wanneer", selection: $kind) {
                            ForEach(ReminderSchedule.Kind.allCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(minHeight: NoahSize.minTap)
                        .noahCompactControlScaling()

                        switch kind {
                        case .eenmalig:
                            DatePicker("Datum en tijd", selection: $onceDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .noahInputBox()
                        case .dagelijks:
                            DatePicker("Tijd", selection: $time, displayedComponents: .hourAndMinute)
                                .noahInputBox()
                        case .wekelijks:
                            DatePicker("Tijd", selection: $time, displayedComponents: .hourAndMinute)
                                .noahInputBox()
                            FlowLayout {
                                ForEach(1...7, id: \.self) { day in
                                    NoahChoiceChip(title: Weekdays.shortNames[day]!, isSelected: weekdays.contains(day)) {
                                        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                                    }
                                    .accessibilityLabel(Text(verbatim: Weekdays.names[day]!))
                                }
                            }
                        }
                        Text(verbatim: ScheduleFormatter.describe(schedule))
                            .font(NoahFont.subheadline)
                            .foregroundColor(NoahColor.accent)
                    }
                    .environment(\.timeZone, DutchFormat.timeZone)
                    .environment(\.locale, DutchFormat.locale)
                }

                NoahField(label: "Hoe herinnert Noah eraan?") {
                    VStack(spacing: NoahSpacing.s) {
                        NoahOptionCard(title: "Noah belt op dat moment", subtitle: "Handig voor iets op een vast tijdstip, zoals een afspraak.", isSelected: input.delivery == .bellen) {
                            input.delivery = .bellen
                        }
                        NoahOptionCard(title: "In het volgende gesprek", subtitle: "Noah brengt het rustig ter sprake.", isSelected: input.delivery == .inGesprek) {
                            input.delivery = .inGesprek
                        }
                    }
                }

                NoahTextField(label: "Notitie (optioneel)", text: Binding(get: { input.notes ?? "" }, set: { input.notes = $0 }),
                              prompt: "Bijvoorbeeld: de witte na het ontbijt", multiline: true)

                Toggle(isOn: $input.active) {
                    Text("Actief").font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                }
                .noahInputBox()

                if let error { NoahNotice(kind: .error, text: error) }

                ReminderDisclaimer()

                if case .edit = target {
                    Button(role: .destructive) { confirmsDelete = true } label: {
                        NoahButtonLabel(title: "Herinnering verwijderen", systemImage: "trash")
                    }
                    .buttonStyle(.noah(.quiet))
                    .foregroundColor(NoahColor.dangerText)
                }
            }
            .padding(NoahSpacing.screen)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahScreenBackground()
        .navigationTitle(isNew ? "Nieuwe herinnering" : "Herinnering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                AsyncToolbarButton(title: "Bewaar", isDisabled: !isValid) { await save() }
            }
        }
        .confirmationDialog("Herinnering verwijderen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { Task { await delete() } }
            Button("Annuleren", role: .cancel) {}
        }
        .onAppear(perform: populate)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var isValid: Bool {
        !input.title.trimmingCharacters(in: .whitespaces).isEmpty && (kind != .wekelijks || !weekdays.isEmpty)
    }

    private var schedule: ReminderSchedule {
        switch kind {
        case .eenmalig: return .once(at: onceDate)
        case .dagelijks: return .daily(time: DutchFormat.timeString(from: time))
        case .wekelijks: return .weekly(time: DutchFormat.timeString(from: time), weekdays: weekdays.sorted())
        }
    }

    private func populate() {
        guard !didLoad else { return }
        didLoad = true
        guard case .edit(let reminder) = target else { return }
        input = ReminderInput(reminder: reminder)
        switch reminder.schedule {
        case .once(let at):
            kind = .eenmalig
            onceDate = at
        case .daily(let value):
            kind = .dagelijks
            time = DutchFormat.date(fromTime: value)
        case .weekly(let value, let days):
            kind = .wekelijks
            time = DutchFormat.date(fromTime: value)
            weekdays = Set(days)
        case .unknown:
            break
        }
    }

    private func save() async {
        error = nil
        if kind == .eenmalig, onceDate < Date() {
            error = "Kies een moment in de toekomst."
            return
        }
        input.schedule = schedule
        do {
            switch target {
            case .new:
                guard let id = session.selected?.id else { return }
                _ = try await session.api.createReminder(elderlyId: id, input)
                createdBefore = true
            case .edit(let reminder):
                _ = try await session.api.updateReminder(reminderId: reminder.id, input)
            }
            session.dataChanged()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }

    private func delete() async {
        guard case .edit(let reminder) = target else { return }
        do {
            try await session.api.deleteReminder(reminderId: reminder.id)
            session.dataChanged()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}
