import SwiftUI

/// First screen when nothing is set up: who is this phone for?
struct WelcomeFlowView: View {
    enum Step: Hashable {
        case caregiverIntro
        case signIn
        case phoneSignIn
        case pairing
        /// v2.3: the older person signs up with their own phone number.
        case elderSignUp
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

                    VStack(spacing: NoahSpacing.m) {
                        WelcomeChoiceCard(
                            systemImage: "person.2.fill",
                            title: "Ik ben mantelzorger",
                            subtitle: "Ik stel Noah in voor een naaste en kijk mee hoe het gaat."
                        ) {
                            app.welcomeNotice = nil
                            path.append(.caregiverIntro)
                        }
                        .accessibilityIdentifier("welcome.caregiver")

                        // v2.3: the older person can start on their own, as clearly as the others.
                        WelcomeChoiceCard(
                            systemImage: "mic.fill",
                            title: "Ik wil zelf met Noah praten",
                            subtitle: "U meldt zich aan met uw eigen telefoonnummer."
                        ) {
                            app.welcomeNotice = nil
                            path.append(.elderSignUp)
                        }
                        .accessibilityIdentifier("welcome.self")

                        WelcomeChoiceCard(
                            systemImage: "iphone.radiowaves.left.and.right",
                            title: "Deze telefoon koppelen met een code",
                            subtitle: "Met de code van 6 cijfers van uw familie."
                        ) {
                            app.welcomeNotice = nil
                            path.append(.pairing)
                        }
                        .accessibilityIdentifier("welcome.elder")
                    }

                    #if DEBUG
                    if app.isMock {
                        NoahNotice(kind: .warning, text: "Demo-modus: de app gebruikt voorbeeldgegevens en praat niet met de echte server.")
                    }
                    #endif
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
                    case .elderSignUp:
                        ElderSignUpView()
                    }
                }
                .noahPushedScreen()
                .hidesWhileCovered(ownDepth: (path.firstIndex(of: step) ?? 0) + 1, stackDepth: path.count)
            }
        }
        #if DEBUG
        .confirmationDialog("Ontwikkelaarsopties", isPresented: $showsDebugToggle, titleVisibility: .visible) {
            Button(app.isMock ? "Demo-modus uitzetten" : "Demo-modus aanzetten") {
                app.setMockMode(!app.isMock)
            }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("In de demo-modus werkt de hele app met voorbeeldgegevens, zonder server en zonder ElevenLabs.")
        }
        #endif
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
            #if DEBUG
            // Hidden demo toggle: Debug builds only (never in TestFlight or the App Store).
            .onTapGesture {
                logoTaps += 1
                if logoTaps >= 5 {
                    logoTaps = 0
                    showsDebugToggle = true
                }
            }
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "HelloNoah"))
            .accessibilityAddTraits(.isHeader)

            Text("Welkom")
                .font(NoahFont.largeTitle).noahTitleScaling()
                .foregroundColor(NoahColor.text)
            Text("Noah is een warme metgezel om mee te praten.")
                .font(NoahFont.bodyText)
                .foregroundColor(NoahColor.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("Hoe wilt u beginnen?")
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
            case "elderSignUp", "elderSignUpCode", "familyLinked": path = [.elderSignUp]
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
                NoahIconBadge(systemName: systemImage, size: 44)
                VStack(alignment: .leading, spacing: NoahSpacing.xs) {
                    Text(title)
                        .font(NoahFont.Elder.bodyStrong)
                        .foregroundColor(NoahColor.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle)
                        .font(NoahFont.bodyText)
                        .foregroundColor(NoahColor.textSoft)
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
            // Huge targets for everyone who opens the app for the first time (also older people).
            .frame(maxWidth: .infinity, minHeight: NoahSize.elderButton + NoahSpacing.l, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).fill(NoahColor.surface))
            .overlay(RoundedRectangle(cornerRadius: NoahRadius.large, style: .continuous).strokeBorder(NoahColor.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: NoahRadius.large))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
