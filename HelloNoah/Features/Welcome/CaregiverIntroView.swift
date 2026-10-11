import SwiftUI

/// Four welcome slides for the caregiver (informal "je").
struct CaregiverIntroView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private struct Slide {
        let systemImage: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let slides: [Slide] = [
        Slide(systemImage: "heart.fill",
              title: "Waardig ouder worden",
              body: "Noah is een warme metgezel voor je vader, moeder of naaste. Iemand die luistert, onthoudt en er altijd is, ook als jij er even niet bent. Want eenzaamheid hoort niet bij ouder worden."),
        Slide(systemImage: "bubble.left.and.bubble.right.fill",
              title: "Wat Noah doet",
              body: "Noah maakt een praatje, haalt herinneringen op, bewaart het levensverhaal en helpt met de dag: van pillen tot verjaardagen. Gewoon door te praten, via de app of een gewoon telefoonnummer. Noah is een AI, geen mens, en zegt dat ook eerlijk."),
        Slide(systemImage: "chart.line.uptrend.xyaxis",
              title: "Wat jij ziet",
              body: "Korte samenvattingen van de gesprekken, hoe de stemming is en een seintje als er iets lijkt te spelen. Zo weet je hoe het gaat, ook op afstand. Samen met familie, als je wilt."),
        Slide(systemImage: "lock.shield.fill",
              title: "Privacy voorop",
              body: "Geluidsopnames worden niet bewaard. Alle gegevens staan versleuteld op servers in de EU, volgens de AVG. Je kunt alles op elk moment inzien, exporteren of verwijderen."),
    ]

    var body: some View {
        VStack(spacing: NoahSpacing.l) {
            TabView(selection: $page) {
                ForEach(slides.indices, id: \.self) { index in
                    slideView(slides[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            Button {
                if page < slides.count - 1 {
                    withAnimation(NoahMotion.standard) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < slides.count - 1 ? "Volgende" : "Aan de slag")
            }
            .buttonStyle(.noah(.primary))
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.bottom, NoahSpacing.m)
            .noahReadableWidth()
            .accessibilityIdentifier("intro.next")
        }
        .noahScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if page < slides.count - 1 {
                    Button("Overslaan", action: onFinish)
                }
            }
        }
    }

    private func slideView(_ slide: Slide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoahSpacing.l) {
                Image(systemName: slide.systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(NoahColor.onAccent)
                    .frame(width: 96, height: 96)
                    .background(Circle().fill(NoahColor.accent))
                    .shadow(color: NoahColor.accent.opacity(0.4), radius: 24)
                    .padding(.top, NoahSpacing.xl)
                    .accessibilityHidden(true)
                Text(slide.title)
                    .font(NoahFont.largeTitle).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(slide.body)
                    .font(NoahFont.body(19, relativeTo: .body))
                    .foregroundColor(NoahColor.textSoft)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, NoahSpacing.screen)
            .padding(.bottom, NoahSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .noahReadableWidth()
        }
    }
}
