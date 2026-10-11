import SwiftUI

/// Loading, empty, error and offline states. Every data screen uses these.

struct LoadingStateView: View {
    var message: LocalizedStringKey = "Even geduld…"
    var large = false

    var body: some View {
        VStack(spacing: NoahSpacing.m) {
            ProgressView()
                .controlSize(.large)
                .tint(NoahColor.accent)
            Text(message)
                .font(large ? NoahFont.Elder.body : NoahFont.callout)
                .foregroundColor(NoahColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(NoahSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    var large = false

    var body: some View {
        VStack(spacing: NoahSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: large ? 56 : 44, weight: .regular))
                .foregroundColor(NoahColor.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(large ? NoahFont.Elder.title2 : NoahFont.title3)
                .foregroundColor(NoahColor.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(large ? NoahFont.Elder.body : NoahFont.callout)
                    .foregroundColor(NoahColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.noah(.primary, size: large ? .elder : .regular, fullWidth: false))
                    .padding(.top, NoahSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoahSpacing.xl)
        .padding(.horizontal, NoahSpacing.l)
    }
}

struct ErrorStateView: View {
    let message: String
    var isOffline = false
    var large = false
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: NoahSpacing.m) {
            Image(systemName: isOffline ? "wifi.slash" : "cloud.drizzle")
                .font(.system(size: large ? 56 : 44))
                .foregroundColor(NoahColor.accent)
                .accessibilityHidden(true)
            Text(isOffline ? "Geen verbinding" : "Dat lukte even niet")
                .font(large ? NoahFont.Elder.title2 : NoahFont.title3)
                .foregroundColor(NoahColor.text)
                .multilineTextAlignment(.center)
            Text(verbatim: message)
                .font(large ? NoahFont.Elder.body : NoahFont.callout)
                .foregroundColor(NoahColor.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button(action: retry) {
                    NoahButtonLabel(title: "Opnieuw proberen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.noah(.secondary, size: large ? .elder : .regular, fullWidth: false))
                .padding(.top, NoahSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NoahSpacing.xl)
        .padding(.horizontal, NoahSpacing.l)
        .accessibilityElement(children: .contain)
    }
}

/// Thin banner shown at the top of the caregiver interface while offline.
struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: NoahSpacing.xs) {
            Image(systemName: "wifi.slash").accessibilityHidden(true)
            Text("Geen internetverbinding. Je ziet de laatst geladen gegevens.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(NoahFont.footnote)
        .foregroundColor(NoahColor.onAccent)
        .padding(.horizontal, NoahSpacing.m)
        .padding(.vertical, NoahSpacing.xs)
        .frame(maxWidth: .infinity)
        .background(NoahColor.accent)
        .accessibilityElement(children: .combine)
    }
}

/// Load state for a screen's data.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// Switches between loading, error and content for a `Loadable`.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var large = false
    var loadingMessage: LocalizedStringKey = "Even geduld…"
    let retry: () -> Void
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView(message: loadingMessage, large: large)
        case .failed(let error):
            ErrorStateView(message: large ? error.elderMessage : error.userMessage, isOffline: error.isOffline, large: large, retry: retry)
        case .loaded(let value):
            content(value)
        }
    }
}
