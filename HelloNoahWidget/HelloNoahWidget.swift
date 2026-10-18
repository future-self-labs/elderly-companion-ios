import SwiftUI
import WidgetKit

// One-tap "Praat met Noah" widgets. Tapping opens `hellonoah://praat?bron=widget&t=<token>`;
// with the app's per-install token (shared Keychain group, see `WidgetLaunch`) the conversation
// starts right away. Without it the app shows one big start button first, like for any other link.

struct NoahEntry: TimelineEntry {
    let date: Date
    let talkURL: URL
}

struct NoahProvider: TimelineProvider {
    private func entry() -> NoahEntry {
        NoahEntry(date: Date(), talkURL: WidgetLaunch.talkURL(token: WidgetLaunch.storedToken()))
    }

    func placeholder(in context: Context) -> NoahEntry { NoahEntry(date: Date(), talkURL: WidgetLaunch.talkURL(token: nil)) }

    func getSnapshot(in context: Context, completion: @escaping (NoahEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NoahEntry>) -> Void) {
        // The app reloads the timeline when it creates the token.
        completion(Timeline(entries: [entry()], policy: .never))
    }
}

struct NoahWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NoahEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Noah")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .widgetURL(entry.talkURL)
            .accessibilityLabel(Text("Praat met Noah"))
        case .systemMedium:
            HStack(spacing: NoahSpacing.m) {
                orb(size: 96)
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    Text("Praat met Noah")
                        .font(NoahFont.display(26, relativeTo: .title))
                        .foregroundColor(NoahColor.text)
                        .minimumScaleFactor(0.7)
                    Text("Eén tik en Noah luistert.")
                        .font(NoahFont.body(15, relativeTo: .subheadline))
                        .foregroundColor(NoahColor.textSoft)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .padding(NoahSpacing.m)
            .widgetURL(entry.talkURL)
            .noahWidgetBackground()
        default:
            VStack(spacing: NoahSpacing.s) {
                orb(size: 70)
                Text("Praat met Noah")
                    .font(NoahFont.semibold(15, relativeTo: .headline))
                    .foregroundColor(NoahColor.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .padding(NoahSpacing.s)
            .widgetURL(entry.talkURL)
            .noahWidgetBackground()
        }
    }

    private func orb(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [NoahColor.accent.opacity(0.35), .clear], center: .center, startRadius: size * 0.3, endRadius: size * 0.75))
                .frame(width: size * 1.4, height: size * 1.4)
            Circle()
                .fill(LinearGradient(colors: [NoahColor.accentHighlight, NoahColor.accent, NoahColor.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(NoahColor.onAccent)
        }
        .frame(width: size * 1.1, height: size * 1.1)
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func noahWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { NoahColor.ground }
        } else {
            background(NoahColor.ground)
        }
    }
}

struct HelloNoahWidget: Widget {
    let kind = "HelloNoahTalkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NoahProvider()) { entry in
            NoahWidgetView(entry: entry)
        }
        .configurationDisplayName("Praat met Noah")
        .description("Met één tik een gesprek met Noah beginnen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct HelloNoahWidgets: WidgetBundle {
    var body: some Widget {
        HelloNoahWidget()
    }
}
