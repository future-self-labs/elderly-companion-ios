import SwiftUI

/// Life story by category or as a timeline. Beheerders can add, edit and delete.
struct LifeStoryListView: View {
    enum Mode: Hashable { case topics, timeline }

    @EnvironmentObject private var session: CaregiverSession
    @State private var entries: [LifeStoryEntry] = []
    @State private var state: Loadable<Void> = .idle
    @State private var mode: Mode = .topics
    @State private var filter: LifeStoryCategory?
    @State private var editing: LifeStoryEditorTarget?
    @State private var loadedKey: String?

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            if session.selected == nil {
                NoElderlySelectedView()
            } else {
                Picker("Weergave", selection: $mode) {
                    Text("Onderwerpen").tag(Mode.topics)
                    Text("Tijdlijn").tag(Mode.timeline)
                }
                .pickerStyle(.segmented)
                .frame(minHeight: NoahSize.minTap)
                .noahCompactControlScaling()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NoahSpacing.xs) {
                        NoahChoiceChip(title: "Alles", isSelected: filter == nil) { filter = nil }
                        ForEach(LifeStoryCategory.knownCases, id: \.self) { category in
                            NoahChoiceChip(title: category.label, isSelected: filter == category) { filter = category }
                        }
                    }
                }

                if entries.isEmpty {
                    LoadableView(state: state, retry: { Task { await load() } }) { _ in
                        EmptyStateView(systemImage: "book.closed",
                                       title: filter == nil ? "Het levensverhaal is nog leeg" : "Nog niets over \(filter!.label.lowercased())",
                                       message: "Tijdens de gesprekken bewaart Noah mooie herinneringen. Je kunt ook zelf een herinnering toevoegen.")
                    }
                } else {
                    Text(entries.count == 1 ? "1 herinnering" : "\(entries.count) herinneringen")
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                    switch mode {
                    case .topics: topics
                    case .timeline: timeline
                    }
                }
            }
        }
        .navigationTitle("Levensverhaal")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { ElderlySwitcher() }
            ToolbarItem(placement: .navigationBarTrailing) {
                if session.permissions.canEditLifeStory {
                    Button {
                        editing = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Herinnering toevoegen"))
                }
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack { LifeStoryEditorView(target: target) }
                .environmentObject(session)
        }
        .refreshable { await load() }
        .task(id: "\(session.reloadKey.elderlyId ?? "")-\(session.reloadKey.version)-\(filter?.rawValue ?? "all")") { await load() }
    }

    private var topics: some View {
        let groups = LifeStoryCategory.allCases.compactMap { category -> (LifeStoryCategory, [LifeStoryEntry])? in
            let items = entries.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
        return ForEach(groups, id: \.0) { category, items in
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                Label(category.label, systemImage: category.systemImage)
                    .font(NoahFont.title3)
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { entry in
                    NavigationLink(value: CaregiverRoute.lifeStoryEntry(entry)) {
                        LifeStoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, NoahSpacing.xs)
        }
    }

    private var timeline: some View {
        let sorted = entries.sorted { ($0.year ?? Int.max) < ($1.year ?? Int.max) }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(sorted) { entry in
                HStack(alignment: .top, spacing: NoahSpacing.m) {
                    VStack(spacing: 0) {
                        Text(verbatim: entry.year.map(String.init) ?? "–")
                            .font(NoahFont.semibold(14, relativeTo: .subheadline))
                            .foregroundColor(NoahColor.accent)
                            .frame(width: 52)
                        Rectangle()
                            .fill(NoahColor.divider)
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                    }
                    NavigationLink(value: CaregiverRoute.lifeStoryEntry(entry)) {
                        LifeStoryRow(entry: entry, showsYear: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, NoahSpacing.m)
                }
            }
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        let key = "\(id)-\(filter?.rawValue ?? "all")"
        if loadedKey != key { entries = []; state = .loading }
        do {
            var all: [LifeStoryEntry] = []
            var cursor: String?
            repeat {
                let page = try await session.api.lifeStory(elderlyId: id, category: filter, cursor: cursor, limit: 50)
                all += page.items
                cursor = page.nextCursor
            } while cursor != nil && all.count < 1000
            entries = all
            loadedKey = key
            state = .loaded(())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, entries.isEmpty { state = .failed(apiError) }
        }
    }
}

struct LifeStoryRow: View {
    let entry: LifeStoryEntry
    var showsYear = true

    var body: some View {
        NoahCard {
            HStack(alignment: .firstTextBaseline, spacing: NoahSpacing.xs) {
                (Text(verbatim: showsYear ? entry.year.map { "\($0) · " } ?? "" : "").font(NoahFont.captionStrong).foregroundColor(NoahColor.accent)
                    + Text(verbatim: entry.category.label + (entry.createdBy == .noah ? " · door Noah" : "")).font(NoahFont.caption).foregroundColor(NoahColor.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if entry.audio != nil {
                    Label("Met stem", systemImage: "waveform")
                        .font(NoahFont.captionStrong)
                        .foregroundColor(NoahColor.accent)
                }
            }
            Text(verbatim: entry.title)
                .font(NoahFont.title3)
                .noahTitleScaling()
                .foregroundColor(NoahColor.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: entry.content)
                .font(NoahFont.callout)
                .foregroundColor(NoahColor.textSoft)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LifeStoryEntryView: View {
    @State var entry: LifeStoryEntry

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LifeStoryEditorTarget?
    @State private var confirmsDelete = false
    @State private var error: String?

    var body: some View {
        NoahScrollScreen {
            HStack(spacing: NoahSpacing.xs) {
                NoahChip(text: entry.category.label, systemImage: entry.category.systemImage, tint: NoahColor.accent)
                if let year = entry.year { NoahChip(text: String(year)) }
            }
            Text(verbatim: entry.title)
                .font(NoahFont.largeTitle).noahTitleScaling()
                .foregroundColor(NoahColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let audio = entry.audio {
                LifeStoryListenCard(audio: audio, name: session.selected?.preferredName ?? "", api: session.api)
            }
            Text(verbatim: entry.content)
                .font(NoahFont.body(18, relativeTo: .body))
                .foregroundColor(NoahColor.textSoft)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            if let quote = entry.quote, !quote.isEmpty {
                QuoteBlock(text: quote)
            }
            if !entry.people.isEmpty {
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    NoahEyebrow(text: "Mensen")
                    NoahChipList(items: entry.people, systemImage: "person.fill")
                }
            }
            if !entry.places.isEmpty {
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    NoahEyebrow(text: "Plaatsen")
                    NoahChipList(items: entry.places, systemImage: "mappin")
                }
            }
            Text(verbatim: footer)
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
            if let conversationId = entry.conversationId {
                NavigationLink(value: CaregiverRoute.conversation(id: conversationId)) {
                    NoahButtonLabel(title: "Bekijk het gesprek", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.noah(.secondary))
            }
            if let error { NoahNotice(kind: .error, text: error) }
            if session.permissions.canEditLifeStory {
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    NoahButtonLabel(title: "Verwijderen", systemImage: "trash")
                }
                .buttonStyle(.noah(.quiet))
                .foregroundColor(NoahColor.danger)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if session.permissions.canEditLifeStory {
                    Button("Bewerk") { editing = .edit(entry) }
                }
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                LifeStoryEditorView(target: target) { updated in entry = updated }
            }
            .environmentObject(session)
        }
        .confirmationDialog("Deze herinnering verwijderen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Verwijderen", role: .destructive) { Task { await delete() } }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Hij verdwijnt uit het levensverhaal, ook voor de andere mantelzorgers.")
        }
    }

    private var footer: String {
        let who = entry.createdBy == .noah ? "Bewaard door Noah" : "Toegevoegd door een mantelzorger"
        guard let created = entry.createdAt else { return who }
        return "\(who), \(DutchFormat.relativeDay(created))"
    }

    private func delete() async {
        do {
            try await session.api.deleteLifeStoryEntry(entryId: entry.id)
            session.dataChanged()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

/// "Luister naar Wim": the voice fragment that belongs to this story, from `startSeconds`.
struct LifeStoryListenCard: View {
    let name: String
    @StateObject private var player: RecordingPlayer

    init(audio: LifeStoryAudio, name: String, api: NoahAPI) {
        self.name = name
        _player = StateObject(wrappedValue: RecordingPlayer(startSeconds: audio.startSeconds, durationHint: audio.durationSeconds) {
            try await api.conversationAudio(conversationId: audio.conversationId)
        })
    }

    var body: some View {
        RecordingPlayerCard(player: player,
                            title: name.isEmpty ? "Luister naar het verhaal" : "Luister naar \(name)",
                            subtitle: "Het verhaal in de eigen woorden van \(name.isEmpty ? "je naaste" : name)")
            .accessibilityIdentifier("lifeStory.listen")
    }
}

enum LifeStoryEditorTarget: Identifiable {
    case new
    case edit(LifeStoryEntry)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let entry): return entry.id
        }
    }
}

struct LifeStoryEditorView: View {
    let target: LifeStoryEditorTarget
    var onSaved: ((LifeStoryEntry) -> Void)?

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var input = LifeStoryInput()
    @State private var yearText = ""
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                NoahField(label: "Onderwerp") {
                    Picker("Onderwerp", selection: $input.category) {
                        ForEach(LifeStoryCategory.knownCases, id: \.self) { Text(verbatim: $0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .noahInputBox()
                }
                NoahTextField(label: "Titel", text: $input.title, prompt: "Bijvoorbeeld: De trouwdag")
                NoahTextField(label: "Het verhaal", text: $input.content, prompt: "Vertel wat er gebeurde…", multiline: true)
                NoahTextField(label: "Jaar", text: $yearText, prompt: "1962", footnote: "Mag leeg blijven als het jaar niet bekend is.", keyboard: .numberPad)
                NoahTagEditor(label: "Mensen", tags: $input.people, prompt: "Naam")
                NoahTagEditor(label: "Plaatsen", tags: $input.places, prompt: "Plaats")
                NoahTextField(label: "Mooi citaat (optioneel)", text: Binding(get: { input.quote ?? "" }, set: { input.quote = $0 }),
                              prompt: "Iets wat letterlijk zo gezegd is")
                if let error { NoahNotice(kind: .error, text: error) }
            }
            .padding(NoahSpacing.screen)
            .noahReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .noahScreenBackground()
        .navigationTitle(isNew ? "Nieuwe herinnering" : "Herinnering bewerken")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                AsyncToolbarButton(title: "Bewaar", isDisabled: !isValid) { await save() }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            if case .edit(let entry) = target {
                input = LifeStoryInput(category: entry.category == .unknown ? .dagelijksLeven : entry.category, title: entry.title,
                                       content: entry.content, year: entry.year, people: entry.people, places: entry.places, quote: entry.quote)
                yearText = entry.year.map(String.init) ?? ""
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var isValid: Bool {
        !input.title.trimmingCharacters(in: .whitespaces).isEmpty && !input.content.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        error = nil
        let year = Int(yearText.filter(\.isNumber))
        if let year, !(1900...2100).contains(year) {
            error = "Vul een jaartal in tussen 1900 en 2100, of laat het veld leeg."
            return
        }
        input.year = year
        do {
            let saved: LifeStoryEntry
            switch target {
            case .new:
                guard let id = session.selected?.id else { return }
                saved = try await session.api.createLifeStoryEntry(elderlyId: id, input)
            case .edit(let entry):
                saved = try await session.api.updateLifeStoryEntry(entryId: entry.id, input)
            }
            onSaved?(saved)
            session.dataChanged()
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

/// Toolbar button that runs async work with a spinner.
struct AsyncToolbarButton: View {
    let title: LocalizedStringKey
    var isDisabled = false
    let action: () async -> Void
    @State private var isRunning = false

    var body: some View {
        if isRunning {
            ProgressView().tint(NoahColor.accent)
        } else {
            Button(title) {
                isRunning = true
                Task {
                    await action()
                    isRunning = false
                }
            }
            .font(NoahFont.bodyStrong)
            .disabled(isDisabled)
        }
    }
}
