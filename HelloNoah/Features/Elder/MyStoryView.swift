import SwiftUI

/// "Mijn verhaal": the life story, read-only, in large text — by topic or by period.
struct MyStoryView: View {
    @Binding var path: [ElderRoute]

    enum Grouping { case topic, period }

    @EnvironmentObject private var session: ElderSession
    @State private var state: Loadable<[LifeStoryEntry]> = .idle
    @State private var grouping: Grouping = .topic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                ElderBackButton()
                Text("Mijn verhaal")
                    .font(NoahFont.Elder.hero).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .accessibilityAddTraits(.isHeader)

                LoadableView(state: state, large: true, retry: { Task { await load() } }) { entries in
                    if entries.isEmpty {
                        EmptyStateView(
                            systemImage: "book.closed.fill",
                            title: "Uw verhaal begint hier",
                            message: "Vertel Noah over vroeger: uw jeugd, uw werk, mooie reizen. Noah schrijft het hier voor u op.",
                            large: true
                        )
                    } else {
                        groupingPicker
                        ForEach(sections(entries), id: \.title) { section in
                            VStack(alignment: .leading, spacing: NoahSpacing.m) {
                                Label {
                                    Text(verbatim: section.title)
                                } icon: {
                                    if let icon = section.icon { Image(systemName: icon).foregroundColor(NoahColor.accent) }
                                }
                                .font(NoahFont.Elder.title2).noahElderTitleScaling()
                                .foregroundColor(NoahColor.text)
                                .accessibilityAddTraits(.isHeader)
                                ForEach(section.entries) { entry in
                                    ElderStoryCard(entry: entry) { path.append(.storyEntry(entry)) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .elderSubscreen()
        .task { if state.value == nil { await load() } }
        .refreshable { await load() }
    }

    private var groupingPicker: some View {
        HStack(spacing: NoahSpacing.s) {
            groupingButton("Per onderwerp", .topic)
            groupingButton("Per periode", .period)
        }
    }

    private func groupingButton(_ title: LocalizedStringKey, _ value: Grouping) -> some View {
        Button {
            grouping = value
        } label: {
            Text(title)
                .font(NoahFont.Elder.label)
                .foregroundColor(grouping == value ? NoahColor.onAccent : NoahColor.text)
                .frame(maxWidth: .infinity, minHeight: NoahSize.elderMinTap)
                .background(Capsule().fill(grouping == value ? NoahColor.accent : NoahColor.surface))
                .overlay(Capsule().strokeBorder(grouping == value ? .clear : NoahColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(grouping == value ? [.isButton, .isSelected] : .isButton)
    }

    struct Section {
        let title: String
        let icon: String?
        let entries: [LifeStoryEntry]
    }

    private func sections(_ entries: [LifeStoryEntry]) -> [Section] {
        switch grouping {
        case .topic:
            return LifeStoryCategory.allCases.compactMap { category in
                let items = entries.filter { $0.category == category }
                return items.isEmpty ? nil : Section(title: category.label, icon: category.systemImage, entries: items)
            }
        case .period:
            return LifeStoryGrouping.byDecade(entries).map { Section(title: $0.title, icon: nil, entries: $0.entries) }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            var all: [LifeStoryEntry] = []
            var cursor: String?
            repeat {
                let page = try await session.api.deviceLifeStory(cursor: cursor, limit: 50)
                all += page.items
                cursor = page.nextCursor
            } while cursor != nil && all.count < 500
            state = .loaded(all)
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }
}

enum LifeStoryGrouping {
    /// "De jaren 60" sections in chronological order; entries without a year last ("Zonder jaartal").
    static func byDecade(_ entries: [LifeStoryEntry]) -> [(title: String, entries: [LifeStoryEntry])] {
        let dated = entries.filter { $0.year != nil }.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        let grouped = Dictionary(grouping: dated) { ($0.year! / 10) * 10 }
        let decades = grouped.keys.sorted().map { decade -> (String, [LifeStoryEntry]) in
            let title = decade >= 2000 ? "Na 2000" : "De jaren \(decade % 100 == 0 ? "00" : String(decade % 100))"
            return (title, grouped[decade] ?? [])
        }
        // Everything from 2000 on shares one section.
        var merged: [(title: String, entries: [LifeStoryEntry])] = []
        for (title, items) in decades {
            if let index = merged.firstIndex(where: { $0.title == title }) {
                merged[index].entries += items
            } else {
                merged.append((title, items))
            }
        }
        let undated = entries.filter { $0.year == nil }
        if !undated.isEmpty { merged.append(("Zonder jaartal", undated)) }
        return merged
    }
}

struct ElderStoryCard: View {
    let entry: LifeStoryEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                if let year = entry.year {
                    Text(verbatim: String(year))
                        .font(NoahFont.Elder.label)
                        .foregroundColor(NoahColor.accent)
                }
                Text(verbatim: entry.title)
                    .font(NoahFont.Elder.title2).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: entry.content)
                    .font(NoahFont.Elder.label)
                    .foregroundColor(NoahColor.textSoft)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack {
                    Spacer()
                    Text("Lees verder")
                        .font(NoahFont.Elder.label)
                        .foregroundColor(NoahColor.accent)
                    Image(systemName: "chevron.right")
                        .foregroundColor(NoahColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(NoahSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
            .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: NoahRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opent het hele verhaal"))
    }
}

struct ElderStoryDetailView: View {
    let entry: LifeStoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                ElderBackButton()
                HStack(spacing: NoahSpacing.s) {
                    NoahChip(text: entry.category.label, systemImage: entry.category.systemImage, tint: NoahColor.accent)
                    if let year = entry.year {
                        NoahChip(text: String(year))
                    }
                }
                Text(verbatim: entry.title)
                    .font(NoahFont.Elder.hero).noahElderTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: entry.content)
                    .font(NoahFont.Elder.body)
                    .foregroundColor(NoahColor.textSoft)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                if let quote = entry.quote, !quote.isEmpty {
                    QuoteBlock(text: quote, large: true)
                }
                if !entry.people.isEmpty {
                    detailLine(title: "Met", value: DutchList.join(entry.people), icon: "person.2.fill")
                }
                if !entry.places.isEmpty {
                    detailLine(title: "Waar", value: DutchList.join(entry.places), icon: "mappin.and.ellipse")
                }
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.vertical, NoahSpacing.m)
            .noahReadableWidth()
        }
        .elderSubscreen()
    }

    private func detailLine(title: LocalizedStringKey, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: NoahSpacing.s) {
            Image(systemName: icon)
                .foregroundColor(NoahColor.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                Text(title).font(NoahFont.Elder.label).foregroundColor(NoahColor.textSecondary)
                Text(verbatim: value).font(NoahFont.Elder.body).foregroundColor(NoahColor.text)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A highlighted quote with an amber bar.
struct QuoteBlock: View {
    let text: String
    var large = false

    var body: some View {
        HStack(alignment: .top, spacing: NoahSpacing.m) {
            RoundedRectangle(cornerRadius: 2)
                .fill(NoahColor.accent)
                .frame(width: 4)
            Text(verbatim: "\u{201C}\(text)\u{201D}")
                .font(large ? NoahFont.Elder.title2 : NoahFont.title3)
                .foregroundColor(NoahColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, NoahSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Citaat: \(text)"))
    }
}
