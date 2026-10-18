import SwiftUI

extension AlertSeverity {
    var color: Color {
        switch self {
        case .nood, .urgent: return NoahColor.dangerText
        case .waarschuwing: return NoahColor.accent
        case .info, .unknown: return NoahColor.textSoft
        }
    }
}

/// Card for one alert, with a coloured severity edge.
struct AlertCard: View {
    let alert: NoahAlert

    var body: some View {
        AdaptiveStack(spacing: NoahSpacing.s) {
            NoahIconBadge(systemName: alert.type.systemImage, tint: alert.severity.color)
            VStack(alignment: .leading, spacing: NoahSpacing.xxs) {
                (Text(verbatim: alert.severity.label).font(NoahFont.captionStrong).foregroundColor(alert.severity.color)
                    + Text(verbatim: " · \(DutchFormat.dayAndTime(alert.createdAt))").font(NoahFont.caption).foregroundColor(NoahColor.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: alert.title)
                    .font(NoahFont.bodyStrong)
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = alert.body {
                    Text(verbatim: body)
                        .font(NoahFont.subheadline)
                        .foregroundColor(NoahColor.textSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if alert.status != .open {
                    Text(verbatim: alert.acknowledgedBy.map { "\(alert.status.label) door \($0)" } ?? alert.status.label)
                        .font(NoahFont.caption)
                        .foregroundColor(NoahColor.textSecondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(NoahFont.footnote)
                .foregroundColor(NoahColor.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(NoahSpacing.m)
        .background(RoundedRectangle(cornerRadius: NoahRadius.card, style: .continuous).fill(NoahColor.surface))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(alert.severity.color)
                .frame(width: 5)
                .padding(.vertical, NoahSpacing.m)
        }
        .overlay(RoundedRectangle(cornerRadius: NoahRadius.card, style: .continuous).strokeBorder(alert.status == .open ? alert.severity.color.opacity(0.6) : NoahColor.border, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct AlertsListView: View {
    @EnvironmentObject private var session: CaregiverSession
    @State private var filter: AlertListFilter = .open
    @State private var items: [NoahAlert] = []
    @State private var nextCursor: String?
    @State private var state: Loadable<Void> = .idle
    @State private var loadMoreFailed = false

    var body: some View {
        NoahScrollScreen(spacing: NoahSpacing.m) {
            Picker("Filter", selection: $filter) {
                Text("Open").tag(AlertListFilter.open)
                Text("Alle").tag(AlertListFilter.all)
            }
            .pickerStyle(.segmented)
            .frame(minHeight: NoahSize.minTap)
            .noahCompactControlScaling()

            if items.isEmpty {
                LoadableView(state: state, retry: { Task { await load() } }) { _ in
                    EmptyStateView(systemImage: "checkmark.seal",
                                   title: filter == .open ? "Geen open meldingen" : "Nog geen meldingen",
                                   message: "Noah laat het je weten als er iets lijkt te spelen, zoals een sombere stemming, een hulpvraag of een mogelijk oplichtingstelefoontje.")
                }
            } else {
                ForEach(items) { alert in
                    NavigationLink(value: CaregiverRoute.alert(id: alert.id)) { AlertCard(alert: alert) }
                        .buttonStyle(.plain)
                }
                if nextCursor != nil {
                    if loadMoreFailed {
                        // One failure must not leave an endless spinner (audit L3).
                        NoahAsyncButton(kind: .quiet, action: loadMore) { Text("Meer meldingen laden") }
                            .accessibilityIdentifier("alerts.loadMore")
                    } else {
                        ProgressView()
                            .tint(NoahColor.accent)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .task { await loadMore() }
                    }
                }
            }
        }
        .navigationTitle("Meldingen")
        .task(id: "\(session.reloadKey.elderlyId ?? "")-\(session.reloadKey.version)-\(filter.rawValue)") { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        if items.isEmpty { state = .loading }
        do {
            let page = try await session.api.alerts(elderlyId: id, status: filter, cursor: nil, limit: 20)
            items = page.items
            nextCursor = page.nextCursor
            state = .loaded(())
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { items = []; state = .failed(apiError) }
        }
    }

    private func loadMore() async {
        guard let id = session.selected?.id, let cursor = nextCursor else { return }
        do {
            let page = try await session.api.alerts(elderlyId: id, status: filter, cursor: cursor, limit: 20)
            items += page.items
            nextCursor = page.nextCursor
            loadMoreFailed = false
        } catch {
            if APIError.from(error) != .cancelled { loadMoreFailed = true }
        }
    }
}

/// One alert: acknowledge (any role), resolve with optional "vals alarm" (beheerder).
struct AlertDetailView: View {
    let alertId: String

    @EnvironmentObject private var session: CaregiverSession
    @State private var state: Loadable<NoahAlert> = .idle
    @State private var elderlyPhone: String?
    @State private var showsResolve = false
    @State private var error: String?

    var body: some View {
        NoahScrollScreen {
            LoadableView(state: state, retry: { Task { await load() } }) { alert in
                content(alert)
            }
        }
        .navigationTitle("Melding")
        .navigationBarTitleDisplayMode(.inline)
        .task { if state.value == nil { await load() } }
        .sheet(isPresented: $showsResolve) {
            if let alert = state.value {
                NavigationStack {
                    ResolveAlertView(alert: alert) { updated in
                        state = .loaded(updated)
                        session.dataChanged()
                        Task { await session.reloadMe() }
                    }
                }
                .environmentObject(session)
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func content(_ alert: NoahAlert) -> some View {
        HStack(spacing: NoahSpacing.xs) {
            NoahChip(text: alert.severity.label, systemImage: alert.type.systemImage, tint: alert.severity.color)
            NoahChip(text: alert.type.label)
        }
        Text(verbatim: alert.title)
            .font(NoahFont.largeTitle).noahTitleScaling()
            .foregroundColor(NoahColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        Text(verbatim: DutchFormat.dayAndTime(alert.createdAt).capitalizedFirst)
            .font(NoahFont.subheadline)
            .foregroundColor(NoahColor.textSecondary)
        if let body = alert.body {
            NoahCard {
                Text(verbatim: body)
                    .font(NoahFont.bodyText)
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        NoahCard {
            NoahRow(icon: alert.status == .afgehandeld ? "checkmark.circle.fill" : (alert.status == .gezien ? "eye.fill" : "circle.dotted"),
                    iconTint: alert.status == .afgehandeld ? NoahColor.positive : NoahColor.accent,
                    title: alert.status.label,
                    subtitle: alert.acknowledgedBy.map { "Door \($0)" },
                    showsChevron: false)
        }

        if alert.severity == .nood || alert.type == .noodgeval {
            NoahNotice(kind: .error, text: "Is er direct gevaar? Bel 112. HelloNoah is geen alarmdienst. Bij een noodgeval krijgen alle mantelzorgers een melding, en sturen en bellen we de noodcontacten één voor één, tot iemand reageert.")
            if let url = URL(string: "tel://112") {
                Link(destination: url) { NoahButtonLabel(title: "Bel 112", systemImage: "phone.fill") }
                    .buttonStyle(.noah(.destructive))
            }
        }

        if let phone = elderlyPhone, let url = URL(string: "tel://\(phone)"), let name = session.selected?.preferredName {
            Link(destination: url) { NoahButtonLabel(title: "Bel \(name)", systemImage: "phone.fill") }
                .buttonStyle(.noah(.secondary))
        }

        if let conversationId = alert.conversationId {
            NavigationLink(value: CaregiverRoute.conversation(id: conversationId)) {
                NoahButtonLabel(title: "Bekijk het gesprek", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(.noah(.secondary))
        }

        if let error { NoahNotice(kind: .error, text: error) }

        if alert.status == .open, session.permissions.canAcknowledgeAlerts {
            NoahAsyncButton(kind: .primary) { await acknowledge(alert) } label: {
                NoahButtonLabel(title: "Ik heb het gezien", systemImage: "eye")
            }
            .accessibilityIdentifier("alert.acknowledge")
        }
        if alert.status != .afgehandeld, session.permissions.canResolveAlerts {
            Button {
                showsResolve = true
            } label: {
                NoahButtonLabel(title: "Afhandelen", systemImage: "checkmark.circle")
            }
            .buttonStyle(.noah(alert.status == .open ? .secondary : .primary))
            .accessibilityIdentifier("alert.resolve")
        }
    }

    private func load() async {
        guard let id = session.selected?.id else { return }
        do {
            var cursor: String?
            var found: NoahAlert?
            repeat {
                let page = try await session.api.alerts(elderlyId: id, status: .all, cursor: cursor, limit: 50)
                found = page.items.first { $0.id == alertId }
                cursor = page.nextCursor
            } while found == nil && cursor != nil
            if let found {
                state = .loaded(found)
            } else {
                state = .failed(.server(status: 404, code: "not_found", message: "Deze melding bestaat niet (meer)."))
            }
            if session.permissions.canView {
                elderlyPhone = try? await session.api.elderly(id: id).phoneNumber
            }
        } catch {
            let apiError = APIError.from(error)
            if apiError != .cancelled { state = .failed(apiError) }
        }
    }

    private func acknowledge(_ alert: NoahAlert) async {
        do {
            state = .loaded(try await session.api.acknowledgeAlert(alertId: alert.id))
            error = nil
            session.dataChanged()
            await session.reloadMe()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}

struct ResolveAlertView: View {
    let alert: NoahAlert
    let onResolved: (NoahAlert) -> Void

    @EnvironmentObject private var session: CaregiverSession
    @Environment(\.dismiss) private var dismiss
    @State private var falseAlarm = false
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Text("Wat is er gebeurd? Met je notitie zien de andere mantelzorgers wat er al gedaan is.")
                    .font(NoahFont.callout)
                    .foregroundColor(NoahColor.textSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $falseAlarm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dit was vals alarm").font(NoahFont.bodyStrong).foregroundColor(NoahColor.text)
                        Text("Er was niets aan de hand.").font(NoahFont.footnote).foregroundColor(NoahColor.textSecondary)
                    }
                }
                .noahInputBox()
                .accessibilityIdentifier("alert.falseAlarm")
                NoahTextField(label: "Notitie (optioneel)", text: $note, prompt: "Bijvoorbeeld: ik heb gebeld, alles is goed", multiline: true)
                if let error { NoahNotice(kind: .error, text: error) }
                NoahAsyncButton("Afhandelen") { await resolve() }
            }
            .padding(NoahSpacing.screen)
        }
        .noahScreenBackground()
        .navigationTitle("Melding afhandelen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annuleren") { dismiss() } }
        }
    }

    private func resolve() async {
        do {
            let updated = try await session.api.resolveAlert(alertId: alert.id, falseAlarm: falseAlarm, note: note)
            onResolved(updated)
            dismiss()
        } catch {
            self.error = APIError.from(error).userMessage
        }
    }
}
