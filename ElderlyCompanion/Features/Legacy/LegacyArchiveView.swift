import SwiftUI

struct LegacyArchiveView: View {
    @State private var selectedTab: ArchiveTab = .audio

    enum ArchiveTab: String, CaseIterable {
        case audio
        case transcripts
        case timeline
        case highlighted

        var label: String {
            switch self {
            case .audio: return "Audio"
            case .transcripts: return "Transcripts"
            case .timeline: return "Timeline"
            case .highlighted: return "Starred"
            }
        }

        var icon: String {
            switch self {
            case .audio: return "mic.fill"
            case .transcripts: return "doc.text.fill"
            case .timeline: return "clock.fill"
            case .highlighted: return "star.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CompanionTheme.Spacing.sm) {
                    ForEach(ArchiveTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation { selectedTab = tab }
                        } label: {
                            Label(tab.label, systemImage: tab.icon)
                                .font(.companionLabel)
                                .padding(.horizontal, CompanionTheme.Spacing.md)
                                .padding(.vertical, CompanionTheme.Spacing.sm)
                                .background(selectedTab == tab ? Color.companionPrimary : Color.companionSurface)
                                .foregroundStyle(selectedTab == tab ? .white : Color.companionTextSecondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CompanionTheme.Spacing.lg)
                .padding(.vertical, CompanionTheme.Spacing.md)
            }

            // Content
            ScrollView {
                VStack(spacing: CompanionTheme.Spacing.lg) {
                    // Empty state
                    VStack(spacing: CompanionTheme.Spacing.lg) {
                        Spacer(minLength: CompanionTheme.Spacing.xxxl)

                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.companionTextTertiary)

                        VStack(spacing: CompanionTheme.Spacing.sm) {
                            Text("Your Life Story")
                                .font(.companionHeadline)
                                .foregroundStyle(Color.companionTextPrimary)

                            Text("Memories captured during conversations with Noah will appear here. Each story is auto-tagged and organized.")
                                .font(.companionBody)
                                .foregroundStyle(Color.companionTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, CompanionTheme.Spacing.xl)
                        }

                        Spacer()
                    }
                }
                .padding(CompanionTheme.Spacing.lg)
            }
        }
        .background(Color.companionBackground)
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        LegacyArchiveView()
    }
}
