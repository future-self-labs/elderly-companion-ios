import SwiftUI

/// One conversation: summary, mood, clarity, topics, signals, emotional moments, transcript.
struct ConversationDetailView: View {
    let conversationId: String

    @EnvironmentObject private var session: CaregiverSession
    @EnvironmentObject private var router: CaregiverRouter
    @State private var state: Loadable<ConversationDetail> = .idle
    @State private var showsTranscript = false

    var body: some View {
        NoahScrollScreen {
            LoadableView(state: state, retry: { Task { await load() } }) { conversation in
                content(conversation)
            }
        }
        .navigationTitle("Gesprek")
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func content(_ c: ConversationDetail) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            Text(verbatim: DutchFormat.dayAndTime(c.startedAt).capitalizedFirst)
                .font(NoahFont.title).noahTitleScaling()
                .foregroundColor(NoahColor.text)
                .accessibilityAddTraits(.isHeader)
            Label {
                Text(verbatim: "\(c.channel.label) · \(DutchFormat.duration(seconds: c.durationSeconds))")
            } icon: {
                Image(systemName: c.channel.systemImage)
            }
            .font(NoahFont.subheadline)
            .foregroundColor(NoahColor.textSecondary)
        }

        if let summary = c.summary {
            NoahCard {
                NoahEyebrow(text: "Samenvatting")
                Text(verbatim: summary)
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack(spacing: NoahSpacing.m) {
            scoreTile(title: "Stemming", value: c.moodScore, label: MoodText.label(c.moodScore), color: NoahColor.mood(c.moodScore))
            scoreTile(title: "Helderheid", value: c.cognitiveClarity, label: MoodText.clarity(c.cognitiveClarity), color: NoahColor.textSoft)
        }

        if !c.concerningSignals.isEmpty {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                NoahSectionHeader(title: "Signalen")
                ForEach(c.concerningSignals, id: \.self) { signal in
                    NoahNotice(kind: .warning, text: signal)
                }
                Text("Noah geeft signalen door om je te helpen opletten. Het is geen medisch oordeel. Twijfel je, overleg dan met de huisarts.")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if !c.topics.isEmpty {
            labeledChips("Onderwerpen", c.topics, icon: nil)
        }
        if !c.moodIndicators.isEmpty {
            labeledChips("Hoe klonk het", c.moodIndicators, icon: nil)
        }

        if !c.emotionalMoments.isEmpty {
            NoahCard {
                NoahEyebrow(text: "Emotionele momenten")
                ForEach(c.emotionalMoments, id: \.self) { moment in
                    Label {
                        Text(verbatim: moment).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "heart.fill").foregroundColor(NoahColor.accent)
                    }
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                }
            }
        }

        if !(c.mentionedPeople.isEmpty && c.mentionedPlaces.isEmpty && c.mentionedDates.isEmpty) {
            NoahCard {
                NoahEyebrow(text: "Genoemd")
                if !c.mentionedPeople.isEmpty { mention("person.2.fill", "Mensen", c.mentionedPeople) }
                if !c.mentionedPlaces.isEmpty { mention("mappin.and.ellipse", "Plaatsen", c.mentionedPlaces) }
                if !c.mentionedDates.isEmpty { mention("calendar", "Tijden", c.mentionedDates) }
            }
        }

        if !c.lifeStoryEntryIds.isEmpty {
            Button {
                router.tab = .lifeStory
            } label: {
                NoahCard {
                    NoahRow(icon: "book.fill",
                            title: c.lifeStoryEntryIds.count == 1 ? "1 herinnering bewaard in het levensverhaal" : "\(c.lifeStoryEntryIds.count) herinneringen bewaard in het levensverhaal",
                            subtitle: "Bekijk het levensverhaal")
                }
            }
            .buttonStyle(.plain)
        }

        if !c.transcript.isEmpty {
            VStack(alignment: .leading, spacing: NoahSpacing.s) {
                Button {
                    withAnimation(NoahMotion.standard) { showsTranscript.toggle() }
                } label: {
                    HStack {
                        Text(showsTranscript ? "Verberg het gesprek" : "Lees het hele gesprek")
                        Spacer()
                        Image(systemName: showsTranscript ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.noah(.secondary))
                .accessibilityIdentifier("conversation.transcriptToggle")

                if showsTranscript {
                    TranscriptView(lines: c.transcript, elderlyName: session.selected?.preferredName ?? "Oudere")
                }
            }
        }
    }

    private func scoreTile(title: LocalizedStringKey, value: Double?, label: String, color: Color) -> some View {
        NoahCard {
            NoahEyebrow(text: title)
            HStack(alignment: .firstTextBaseline, spacing: NoahSpacing.xxs) {
                Text(verbatim: value.map { DutchFormat.decimal($0, digits: $0.rounded() == $0 ? 0 : 1) } ?? "–")
                    .font(NoahFont.statNumber).noahTitleScaling()
                    .foregroundColor(color)
                Text(verbatim: "/ 5")
                    .font(NoahFont.footnote)
                    .foregroundColor(NoahColor.textSecondary)
            }
            Text(verbatim: label)
                .font(NoahFont.subheadline)
                .foregroundColor(NoahColor.textSoft)
        }
        .accessibilityElement(children: .combine)
    }

    private func labeledChips(_ title: LocalizedStringKey, _ items: [String], icon: String?) -> some View {
        VStack(alignment: .leading, spacing: NoahSpacing.xs) {
            NoahEyebrow(text: title)
            NoahChipList(items: items, systemImage: icon)
        }
    }

    private func mention(_ icon: String, _ title: LocalizedStringKey, _ values: [String]) -> some View {
        HStack(alignment: .top, spacing: NoahSpacing.s) {
            Image(systemName: icon)
                .foregroundColor(NoahColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                Text(verbatim: DutchList.join(values)).font(NoahFont.callout).foregroundColor(NoahColor.text)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            state = .loaded(try await session.api.conversation(id: conversationId))
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled, state.value == nil { state = .failed(apiError) }
        }
    }
}

/// Chat-style transcript: Noah left, the older person right.
struct TranscriptView: View {
    let lines: [TranscriptLine]
    let elderlyName: String

    var body: some View {
        VStack(spacing: NoahSpacing.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let isNoah = line.role == .noah
                HStack {
                    if !isNoah { Spacer(minLength: NoahSpacing.xl) }
                    VStack(alignment: isNoah ? .leading : .trailing, spacing: 2) {
                        Text(verbatim: isNoah ? "Noah" : elderlyName)
                            .font(NoahFont.captionStrong)
                            .foregroundColor(isNoah ? NoahColor.accent : NoahColor.textSecondary)
                        Text(verbatim: line.text)
                            .font(NoahFont.callout)
                            .foregroundColor(NoahColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(NoahSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous)
                            .fill(isNoah ? NoahColor.surface : NoahColor.surfaceDeep)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NoahRadius.medium, style: .continuous)
                            .strokeBorder(NoahColor.border, lineWidth: 1)
                    )
                    if isNoah { Spacer(minLength: NoahSpacing.xl) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
