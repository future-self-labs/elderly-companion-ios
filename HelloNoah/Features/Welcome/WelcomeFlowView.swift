import SwiftUI

/// First screen when nothing is set up: who is this phone for?
struct WelcomeFlowView: View {
    enum Step: Hashable {
        case caregiverIntro
        case signIn
        case phoneSignIn
        case pairing
    }

    @EnvironmentObject private var app: AppModel
    @State private var path: [Step] = []
    @State private var logoTaps = 0
    @State private var showsDebugToggle = false
    @State private var prefilledPairingCode: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NoahSpacing.l) {
                    header
                    if let notice = app.welcomeNotice {
                        NoahNotice(kind: .info, text: notice)
                    }
                    if app.isMock {
                        NoahNotice(kind: .warning, text: "Demo-modus: de app gebruikt voorbeeldgegevens en praat niet met de echte server.")
                    }

                    VStack(spacing: NoahSpacing.m) {
                        WelcomeChoiceCard(
                            systemImage: "person.2.fill",
                            title: "Ik ben mantelzorger",
                            subtitle: "Ik stel Noah in voor mijn vader, moeder of een andere naaste, en kijk mee hoe het gaat."
                        ) {
                            app.welcomeNotice = nil
                            path.append(.caregiverIntro)
                        }
                        .accessibilityIdentifier("welcome.caregiver")

                        WelcomeChoiceCard(
                            systemImage: "iphone.radiowaves.left.and.right",
                            title: "Deze telefoon is voor iemand die met Noah gaat praten",
                            subtitle: "Koppel deze telefoon met de code van 6 cijfers van de mantelzorger."
                        ) {
                            app.welcomeNotice = nil
                            path.append(.pairing)
                        }
                        .accessibilityIdentifier("welcome.elder")
                    }

                    Text("Een product van Aldery")
                        .font(NoahFont.footnote)
                        .foregroundColor(NoahColor.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, NoahSpacing.m)
                }
                .padding(.horizontal, NoahSpacing.screen)
                .padding(.vertical, NoahSpacing.l)
                .noahReadableWidth()
            }
            .noahScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .hidesWhileCovered(ownDepth: 0, stackDepth: path.count)
            .navigationDestination(for: Step.self) { step in
                Group {
                    switch step {
                    case .caregiverIntro:
                        CaregiverIntroView { path.append(.signIn) }
                    case .signIn:
                        SignInView { path.append(.phoneSignIn) }
                    case .phoneSignIn:
                        PhoneSignInView()
                    case .pairing:
                        PairingView(initialCode: prefilledPairingCode)
                    }
                }
                .noahPushedScreen()
                .hidesWhileCovered(ownDepth: (path.firstIndex(of: step) ?? 0) + 1, stackDepth: path.count)
            }
        }
        .confirmationDialog("Ontwikkelaarsopties", isPresented: $showsDebugToggle, titleVisibility: .visible) {
            Button(app.isMock ? "Demo-modus uitzetten" : "Demo-modus aanzetten") {
                app.setMockMode(!app.isMock)
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("In de demo-modus werkt de hele app met voorbeeldgegevens, zonder server en zonder ElevenLabs.")
        }
        .onAppear { afterFirstLayout(consumeLinks) }
        .onChange(of: app.pendingLink) { _ in consumeLinks() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NoahSpacing.m) {
            HStack(spacing: NoahSpacing.s) {
                NoahOrb(activity: .idle, diameter: 44)
                    .frame(width: 60, height: 60)
                Text(verbatim: "HelloNoah")
                    .font(NoahFont.display(32, relativeTo: .largeTitle)).noahTitleScaling()
                    .foregroundColor(NoahColor.text)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                logoTaps += 1
                if logoTaps >= 5 {
                    logoTaps = 0
                    showsDebugToggle = true
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "HelloNoah"))
            .accessibilityAddTraits(.isHeader)

            Text("Welkom")
                .font(NoahFont.largeTitle).noahTitleScaling()
                .foregroundColor(NoahColor.text)
            Text("Noah is een warme metgezel om mee te praten. Voor waardig ouder worden, en gemoedsrust voor de familie.")
                .font(NoahFont.bodyText)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("Voor wie is deze telefoon?")
                .font(NoahFont.title3)
                .foregroundColor(NoahColor.text)
                .padding(.top, NoahSpacing.s)
        }
    }

    private func consumeLinks() {
        if let link = app.pendingLink {
            switch link {
            case .pair(let code):
                app.pendingLink = nil
                prefilledPairingCode = code
                path = [.pairing]
            case .invitation:
                // Accepting needs a caregiver account: sign in first, the link is kept.
                path = [.signIn]
            default:
                break
            }
        }
        if let route = DebugRoute.take(scope: "welcome") {
            switch route {
            case "caregiverIntro": path = [.caregiverIntro]
            case "signIn": path = [.caregiverIntro, .signIn]
            case "phoneSignIn": path = [.caregiverIntro, .signIn, .phoneSignIn]
            case "pairing": path = [.pairing]
            default: break
            }
        }
    }
}

struct WelcomeChoiceCard: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdaptiveStack(spacing: NoahSpacing.m) {
                NoahIconBadge(systemName: systemImage, size: 52)
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    Text(title)
                        .font(NoahFont.title3)
                        .foregroundColor(NoahColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(NoahFont.callout)
                        .foregroundColor(NoahColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(NoahFont.headline)
                    .foregroundColor(NoahColor.accent)
                    .padding(.top, NoahSpacing.xs)
                    .accessibilityHidden(true)
            }
            .padding(NoahSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
            .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: NoahRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
